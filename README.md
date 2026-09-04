# LiveKit 自维护 Helm Chart + ArgoCD

此方案不依赖 LiveKit 官方 Helm Chart，只使用官方 LiveKit Server 镜像。

当前默认版本：

```text
livekit/livekit-server:v1.13.4
```

域名：

```text
wss://im-live.djftech.app
```

## 目录

```text
livekit-custom-helm/
├── argocd/
│   ├── livekit-application.yaml
│   └── livekit-dev-application.yaml
├── charts/
│   └── livekit/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
└── scripts/
    ├── create-livekit-secret.sh
    └── sync-webhook-api-key.sh
```

## 1. 创建 API Key Secret

```bash
chmod +x scripts/create-livekit-secret.sh
./scripts/create-livekit-secret.sh
./scripts/sync-webhook-api-key.sh
```

保存脚本输出的：

```text
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
```

Secret 不提交 Git，ArgoCD 只引用现有的 `livekit/livekit-api-keys`。`sync-webhook-api-key.sh` 会从 `keys.yaml` 读取 API Key，并写入 LiveKit webhook 需要的 `webhook-api-key` 字段。

## 2. 推送到你的 Git 仓库

```bash
git init
git add .
git commit -m "deploy livekit with custom helm chart"
git branch -M main
git remote add origin <你的 Git 仓库地址>
git push -u origin main
```

修改：

```text
argocd/livekit-application.yaml
argocd/livekit-dev-application.yaml
```

将 `repoURL` 替换成你的仓库地址。

## 3. 创建 ArgoCD Application

```bash
kubectl apply -f argocd/livekit-application.yaml
argocd app sync livekit
```

检查：

```bash
kubectl -n argocd get application livekit
kubectl -n livekit get pods,svc,ingress,certificate
kubectl -n livekit logs deploy/livekit --tail=200 -f
```

### 开发环境 `livekit-dev`

`livekit-dev` 使用 `livekit-dev` namespace，并将 webhook 覆盖为：

```text
http://im28-api-gateway.im28-dev.svc.cluster.local:8080/v1/livekit/webhook
```

开发环境 Ingress 域名为：

```text
wss://im-dev-live.djftech.app
```

先创建 API Key Secret，再补充 webhook 签名所需的 API Key：

```bash
NAMESPACE=livekit-dev ./scripts/create-livekit-secret.sh
NAMESPACE=livekit-dev ./scripts/sync-webhook-api-key.sh
```

创建并同步 ArgoCD Application：

```bash
kubectl apply -f argocd/livekit-dev-application.yaml
argocd app sync livekit-dev
```

检查运行状态：

```bash
kubectl -n argocd get application livekit-dev
kubectl -n livekit-dev get pods,svc,ingress,certificate
kubectl -n livekit-dev logs deploy/livekit --tail=200 -f
```

`livekit-dev` 除 webhook 和 Ingress 域名外会继承 `charts/livekit/values.yaml` 的其他默认值。如果生产和开发实例部署在同一集群，仍需避免 `7881/TCP` 和 `7882/UDP` 的节点端口冲突。

## 4. DNS 和防火墙

`im-live.djftech.app` 的 A 记录指向 K3s 节点公网 IP。

如果使用 Cloudflare，建议设置为 DNS only（灰云），因为媒体端口需要直连节点。

开放：

```text
80/TCP    nginx Ingress / ACME
443/TCP   HTTPS / WSS
7881/TCP  WebRTC ICE/TCP
7882/UDP  WebRTC 媒体
```

UFW 示例：

```bash
sudo ufw allow 7881/tcp
sudo ufw allow 7882/udp
sudo ufw reload
```

云厂商安全组也要开放相同端口。

## 5. 升级 LiveKit

只修改两个位置：

```yaml
# charts/livekit/Chart.yaml
appVersion: "1.13.4"
```

```yaml
# charts/livekit/values.yaml
image:
  tag: v1.13.4
```

提交到 Git 后，ArgoCD 自动同步：

```bash
git add charts/livekit
git commit -m "upgrade livekit server"
git push
```

## 6. Redis

当前是单节点、单 Pod，不强制启用 Redis。

多节点扩容、Ingress/Egress 或更完整的生产架构需要外部 Redis：

```yaml
livekit:
  redis:
    enabled: true
    address: redis-master.redis.svc.cluster.local:6379
    password: "替换密码"
```

生产环境不要把 Redis 密码直接写入公开 Git；建议后续接 Vault、External Secrets 或 Sealed Secrets。

## 7. Helm 本地验证

```bash
helm lint charts/livekit
helm template livekit charts/livekit --namespace livekit
```
