# boot/systemd

起動のたびに動く systemd ユニットを置く。

ユニット：
- `mycomfy-init.service`：起動のたびにインスタンスストアと S3 Files をマウントする。
- `comfyui.service`：init 完了後に ComfyUI を起動する（127.0.0.1:8188）。
- `mycomfy-self-check.service`：起動後に GPU／マウント／ComfyUI 応答を自己チェックし、結果を SNS へ送る。
- `mycomfy-notify-failure@.service`：失敗通知用。init／comfyui ユニットに `OnFailure=mycomfy-notify-failure@%n.service` を付け、`../scripts/notify-failure.sh` 経由で notify-me の SNS トピックへ publish する。

モデル同期用の sync ユニットは次のマイルストーンで足す。
