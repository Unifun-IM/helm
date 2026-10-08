# LiveKit 自维护 Helm Chart + ArgoCD

此方案不依赖 LiveKit 官方 Helm Chart，只使用官方 LiveKit Server 镜像。

当前默认版本：`livekit/livekit-server:v1.13.9`

四个环境部署在同一个集群。LiveKit 使用 `hostNetwork`，媒体端口直接占用节点端口，所以每个环境有独立的 `portOffset`。同一环境的每个节点只能运行 1 个 Pod。

## 目录

```text
helm/
├── argocd/
│   ├── livekit-application.yaml
│   ├── livekit-dev-application.yaml
│   ├── livekit-p2-application.yaml
│   └── livekit-im99.yaml
├── charts/livekit/
└── scripts/
    ├── create-livekit-secret.sh
    └── sync-webhook-api-key.sh
```

`sync-webhook-api-key.sh` 只是兼容旧命令，会转调创建脚本。

## 环境

| Application | Namespace | 域名 | portOffset | ICE TCP | 媒体 UDP | Webhook |
|---|---|---|---|---|---|---|
| livekit | livekit | `wss://im-live.djftech.app` | 0 | 7881 | 7882 | `im28-api-gateway.im28:8080` |
| livekit-dev | livekit-dev | `wss://im-dev-live.djftech.app` | 10 | 7891 | 7892 | `im28-api-gateway.im28-dev:8080` |
| livekit-p2 | livekit-p2 | `wss://im-p2-live.djftech.app` | 20 | 7901 | 7902 | `im28-api-gateway.im28-p2:8080` |
| livekit-im99 | im99 | `wss://im99-live.djftech.app` | 30 | 7911 | 7912 | `im-api-gateway.im99:8080` |

Webhook 路径都是 `/v1/livekit/webhook`。Application 的 `repoURL` 已指向 `https://github.com/Unifun-IM/helm.git`。

实际端口 = 基准端口 + `livekit.portOffset`。基准端口是 HTTP `7880`、TCP `7881`、UDP `7882`。

## 1. 创建 API Key Secret

一条命令会创建 namespace，并同时写入：

- `keys.yaml`：LiveKit API Key 和 API Secret
- `webhook-api-key`：Webhook 签名用的 API Key

Pod 启动时会读取这两个字段。只写 `keys.yaml` 时，Webhook 环境变量缺失，Pod 无法就绪。

```bash
chmod +x scripts/create-livekit-secret.sh
./scripts/create-livekit-secret.sh --all
```

只处理一个环境：

```bash
NAMESPACE=livekit-dev ./scripts/create-livekit-secret.sh
```

指定已有凭据：

```bash
LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=... NAMESPACE=livekit ./scripts/create-livekit-secret.sh
```

保存首次输出的：

```text
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
```

Secret 不提交 Git，ArgoCD 只引用各 namespace 里已经存在的 `livekit-api-keys`。重复执行不会轮换已有凭据，只会补齐缺失的 `webhook-api-key`。如果对应 Deployment 已经在跑，脚本会重启它，让新的环境变量生效。

## 2. 部署

```bash
kubectl apply -f argocd/livekit-application.yaml
kubectl apply -f argocd/livekit-dev-application.yaml
kubectl apply -f argocd/livekit-p2-application.yaml
kubectl apply -f argocd/livekit-im99.yaml
```

四个 Application 都开了自动同步。检查：

```bash
kubectl -n argocd get application livekit livekit-dev livekit-p2 livekit-im99
kubectl -n livekit get pods,svc,ingress,certificate
kubectl -n livekit logs deploy/livekit --tail=200 -f
```

把 namespace 换成 `livekit-dev`、`livekit-p2` 或 `im99` 即可检查其他环境。Deployment 名称都是 `livekit`。

## 3. DNS 和防火墙

四个域名的 A 记录指向节点公网 IP。使用 Cloudflare 时设为 DNS only（灰云），媒体端口需要直连节点。

所有环境共用：

```text
80/TCP    nginx Ingress / ACME
443/TCP   HTTPS / WSS
```

每个环境再开放上表中的 ICE TCP 和媒体 UDP。UFW 示例：

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 7881/tcp
sudo ufw allow 7882/udp
sudo ufw allow 7891/tcp
sudo ufw allow 7892/udp
sudo ufw allow 7901/tcp
sudo ufw allow 7902/udp
sudo ufw allow 7911/tcp
sudo ufw allow 7912/udp
sudo ufw reload
```

云厂商安全组也要开放这些端口。

## 4. 副本

同一环境的 Pod 会按节点打散。2 个节点最多跑 2 个副本；再增加会一直 Pending，事件是 `didn't have free ports for the requested pod ports`。

滚动更新使用 `maxSurge: 0`、`maxUnavailable: 1`。新 Pod 会等旧 Pod 释放节点端口后再创建。

副本数大于 1 时必须启用 Redis，否则各节点房间状态不互通，Helm 渲染会失败：

```yaml
replicaCount: 2
livekit:
  redis:
    enabled: true
    address: redis-master.redis.svc.cluster.local:6379
    password: "替换密码"
```

不要把 Redis 密码写入公开 Git。生产环境用 Vault、External Secrets 或 Sealed Secrets。

## 5. 升级 LiveKit

同时修改：

```yaml
# charts/livekit/Chart.yaml
appVersion: "1.13.9"
```

```yaml
# charts/livekit/values.yaml
image:
  tag: v1.13.9
```

推送到 `main` 后，ArgoCD 会自动同步。

## 6. 本地验证

```bash
helm lint charts/livekit
helm template livekit charts/livekit --namespace livekit
helm template livekit-dev charts/livekit --namespace livekit-dev --set livekit.portOffset=10
```
