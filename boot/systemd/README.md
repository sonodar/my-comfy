# boot/systemd

起動のたびに動く systemd ユニットを置く。

ユニット：
- `mycomfy-init.service`：起動のたびにインスタンスストアと S3 Files をマウントする。
- `comfyui.service` は init 完了後に ComfyUI を起動する。ComfyUI は Tailscale を含む全 IPv4 インターフェイスの TCP 8188 で待ち受ける。
- `mycomfy-self-check.service`：起動後に GPU／マウント／ComfyUI 応答を自己チェックし、結果を SNS へ送る。
- `mycomfy-notify-failure@.service`：失敗通知用。init／comfyui ユニットに `OnFailure=mycomfy-notify-failure@%n.service` を付け、`../scripts/notify-failure.sh` 経由で notify-me の SNS トピックへ publish する。

モデル同期用の sync ユニットは次のマイルストーンで足す。
