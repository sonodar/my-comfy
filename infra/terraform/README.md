# infra/terraform

EC2（GPU スポット）／S3 バケット／IAM ロールなど、AWS 側リソースの定義を置く。

- **起動テンプレート（Launch Template）もここで管理する**（`launch_template.tf`）。インスタンスタイプ、公式 Deep Learning AMI の指定、スポット設定、IAM インスタンスプロファイル、user-data（`boot/cloud-init/` を参照）を持ち、版管理する。自前 AMI は作らない。

方針：
- インスタンスは使うときに起動し、用が済んだら終了する。常時稼働の課金が発生するリソース（NAT Gateway 等）は作らない。
- EC2 Fleet の `instant` を使い、指定したインスタンスタイプの Spot を1台起動する。AWS は `capacity-optimized` で、候補の AZ から Spot 容量に応じて起動先を選ぶ。
- インスタンスタイプは変数で外出しし、決め打ちしない。選定条件は「GPU VRAM 48GB級／NVMe インスタンスストア搭載／東京リージョンでスポット供給あり／スポット単価が現行以下」で、同性能で安価な新世代が出たら差し替える。デフォルト値は現時点の選択として g6e.xlarge を置く。
- **AMI はインスタンスタイプとペアで選ぶ**。AMI 側の条件は「CPU アーキテクチャがインスタンスタイプと一致する（x86_64／arm64）／その GPU 世代に対応するドライバと CUDA が入っている（公式 Deep Learning AMI の対応版）／ENA・NVMe 対応」。AMI ID は SSM パラメータ参照で取得し、ペアの整合（アーキテクチャ一致など）は plan の時点で検証して落とす。起動時にも `nvidia-smi` で GPU が見えることを確認し、ドライバ非対応なら生成に入る前に失敗として通知する。
- モデル置き場と成果物置き場の S3 バケットはここで作る。S3 Files のファイルシステムとマウントターゲットもここで作る。マウントターゲットは `subnet_ids` で指定した AZ 分（a/c/d）を作る。作成自体は無料で、S3 Files の課金はキャッシュに載ったデータと読み書き分だけなので、使わない AZ 分を作っても費用は増えない。Fleet は同じサブネットを起動候補にし、起動後にインスタンスが同じ AZ のマウントターゲットに接続する。
- 個人の値（アカウント ID、リージョン等）は tfvars で外出しし、コードに書かない。
- notify-me 側の SNS トピックはこのリポジトリでは作らない（向こうの Terraform が管理する）。ここではトピック ARN を参照するだけ。
- 起動用バンドル（`boot/` 一式の zip）は Terraform が S3 へ置く。user-data はそれを取って `install.sh` を実行する。

## 実行手順

1. `terraform.tfvars.example` をコピーして `terraform.tfvars` を作り、VPC、パブリックサブネット、notify-me の SNS トピック ARN を入れる。`subnet_ids` は AZ ごとに1つ指定する。`subnet_id` はテンプレートから直接起動する場合に使うため、`subnet_ids` の中から選ぶ。
2. `terraform init && terraform plan && terraform apply`
3. リポジトリのルートで次のコマンドを実行し、Spot を1台起動する。AWS CLI は Terraform と同じアカウント、リージョンに接続する。

   ```sh
   config=$(terraform -chdir=infra/terraform output -json spot_fleet_config) &&
     aws ec2 create-fleet --cli-input-json "$config"
   ```

   起動したインスタンスの ID は応答の `Instances` に入る。起動できなかった場合は `Errors` に理由が入る。

4. notify-me（LINE）で起動結果を確認する。通知は日本語で、時刻は JST。初回セットアップに失敗したときは通知に工程名が入り、詳細はインスタンス内の `/var/log/mycomfy/install.log` に残る。自己チェックの結果は `/var/log/mycomfy/boot-check.json` で確認できる。
5. 用が済んだらインスタンスを終了する。Terraform で管理しているリソースも不要なら `terraform destroy` を実行する。

既存環境でセキュリティグループの送信ルールを独立した Terraform リソースに切り替えるときは、AWS 上の同じルールを対応するリソースにインポートしてから plan を確認する。既存の HTTPS や S3 Files 用のルールを再作成する必要はない。
