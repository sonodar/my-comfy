# infra/terraform

EC2（GPU スポット）／S3 バケット／IAM ロールなど、AWS 側リソースの定義を置く。

- **起動テンプレート（Launch Template）もここで管理する**（`launch_template.tf`）。インスタンスタイプ、公式 Deep Learning AMI の指定、スポット設定、IAM インスタンスプロファイル、user-data（`boot/cloud-init/` を参照）を持ち、版管理する。自前 AMI は作らない。

方針：
- インスタンスは普段停止する前提。常時稼働の課金が発生するリソース（NAT Gateway 等）は作らない。
- 起動方式はマイルストーン1では単一タイプ・単一 AZ のスポット決め打ちだが、実運用ではスポット在庫切れ（InsufficientInstanceCapacity）が起こりうる（2026-11-24 に PoC で実際に発生）。実運用のマイルストーンで、複数 AZ × 複数タイプへの分散（EC2 Fleet または ASG の capacity-optimized）と、スポットが取れない場合のオンデマンドへのフォールバックを入れる。オンデマンド容量予約は「普段は停止」の予算前提と合わないため採らない。
- インスタンスタイプは変数で外出しし、決め打ちしない。選定条件は「GPU VRAM 48GB級／NVMe インスタンスストア搭載／東京リージョンでスポット供給あり／スポット単価が現行以下」で、同性能で安価な新世代が出たら差し替える。デフォルト値は現時点の選択として g6e.xlarge を置く。
- **AMI はインスタンスタイプとペアで選ぶ**。AMI 側の条件は「CPU アーキテクチャがインスタンスタイプと一致する（x86_64／arm64）／その GPU 世代に対応するドライバと CUDA が入っている（公式 Deep Learning AMI の対応版）／ENA・NVMe 対応」。AMI ID は SSM パラメータ参照で取得し、ペアの整合（アーキテクチャ一致など）は plan の時点で検証して落とす。起動時にも `nvidia-smi` で GPU が見えることを確認し、ドライバ非対応なら生成に入る前に失敗として通知する。
- モデル置き場と成果物置き場の S3 バケットはここで作る。S3 Files のファイルシステムとマウントターゲットもここで作る。マウントターゲットは `subnet_ids` で指定した AZ 分（a/c/d）を作る。作成自体は無料で、S3 Files の課金はキャッシュに載ったデータと読み書き分だけなので、使わない AZ 分を作っても費用は増えない。インスタンスが使うサブネットは `subnet_id` の1つだけで、使う AZ を切り替えてもマウントターゲットは作り直しにならない。
- 個人の値（アカウント ID、リージョン等）は tfvars で外出しし、コードに書かない。
- notify-me 側の SNS トピックはこのリポジトリでは作らない（向こうの Terraform が管理する）。ここではトピック ARN を参照するだけ。
- 起動用バンドル（`boot/` 一式の zip）は Terraform が S3 へ置く。user-data はそれを取って `install.sh` を実行する。

## マイルストーン 1 の実行手順

1. `terraform.tfvars.example` をコピーして `terraform.tfvars` を作り、VPC／サブネット（`subnet_id` はインスタンスが使う AZ のもの、`subnet_ids` は a/c/d 分。いずれもインターネットに出られるパブリックサブネット）／notify-me の SNS トピック ARN を入れる。
2. `terraform init && terraform plan && terraform apply`
3. コンソールか AWS CLI で起動テンプレートからインスタンスを立てる。
4. 結果は notify-me（LINE）に届く。成功なら `boot check: ok`、失敗なら失敗項目が届く。詳細はインスタンス内の `/var/log/mycomfy/boot-check.json` と `/var/log/mycomfy/install.log`（Session Manager 経由で確認）。
5. 用が済んだらインスタンスを停止し、不要なら `terraform destroy`。
