# boot/cloud-init

初回起動時の user-data を置く。

やること：
- `/etc/mycomfy/env` に個人値（通知先 SNS、S3 Files ID、ComfyUI の版など）を落とす。
- user-data に埋め込んだ通知コマンドを `/usr/local/bin/notify.sh` に配置する。バンドルの取得や展開、初回セットアップが失敗した場合は、notify-me の SNS トピックへ失敗箇所を送る。
- S3 から boot/ バンドル（`boot/mycomfy-boot.zip`）を取って展開し、`../install.sh` を呼ぶ。

バンドルを展開したあとは `install.sh` がマウントから ComfyUI の起動と自己チェックまでを実行する。同じ EC2 を再起動すると user-data が再実行されないため、ComfyUI は自動起動しない。
