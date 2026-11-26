# infra/terraform

EC2（GPU）／S3 バケット／IAM ロールなど、AWS 側リソースの定義を置く。

- **起動テンプレート（Launch Template）もここで管理する**（`launch_template.tf`）。公式 Deep Learning AMI、IAM インスタンスプロファイル、user-data（`boot/cloud-init/` を参照）を指定する。Fleet が使うインスタンスタイプ候補と S3 Files の ID は、起動テンプレートのタグから取得する。

方針：
- インスタンスは使うときに起動し、用が済んだら終了する。常時稼働の課金が発生するリソース（NAT Gateway 等）は作らない。
- EC2 Fleet の `instant` を使う。PoC 中は `capacity-optimized` で Spot を1台試し、Fleet の応答で起動が0台と分かったときだけオンデマンドを1台試す。
- Fleet のインスタンスタイプ候補は `g6e.xlarge` と `g6e.2xlarge` が既定。どちらも GPU メモリ48 GB級で、50 GB以上の NVMe インスタンスストアを備える。候補を変更するときは `spot_fleet_instance_types` を指定する。
- **AMI はインスタンスタイプとペアで選ぶ**。AMI 側の条件は「CPU アーキテクチャがインスタンスタイプと一致する（x86_64／arm64）／その GPU 世代に対応するドライバと CUDA が入っている（公式 Deep Learning AMI の対応版）／ENA・NVMe 対応」。AMI ID は SSM パラメータ参照で取得し、ペアの整合（アーキテクチャ一致など）は plan の時点で検証して落とす。起動時にも `nvidia-smi` で GPU が見えることを確認し、ドライバ非対応なら生成に入る前に失敗として通知する。
- モデル置き場と成果物置き場の S3 バケットはここで作る。S3 Files のファイルシステムとマウントターゲットもここで作る。マウントターゲットは `subnet_ids` で指定した AZ 分（a/c/d）を作る。作成自体は無料で、S3 Files の課金はキャッシュに載ったデータと読み書き分だけなので、使わない AZ 分を作っても費用は増えない。Fleet は同じサブネットを起動候補にし、起動後にインスタンスが同じ AZ のマウントターゲットに接続する。
- 個人の値（アカウント ID、リージョン等）は tfvars で外出しし、コードに書かない。
- notify-me 側の SNS トピックはこのリポジトリでは作らない（向こうの Terraform が管理する）。ここではトピック ARN を参照するだけ。
- 起動用バンドル（`boot/` 一式の zip）は Terraform が S3 へ置く。user-data はそれを取って `install.sh` を実行する。

## 実行手順

1. `terraform.tfvars.example` をコピーして `terraform.tfvars` を作り、VPC、パブリックサブネット、notify-me の SNS トピック ARN を入れる。`subnet_ids` は AZ ごとに1つ指定する。`subnet_id` はテンプレートから直接起動する場合に使うため、`subnet_ids` の中から選ぶ。
2. `terraform init && terraform plan && terraform apply`
3. リポジトリのルートで次のコマンドを実行し、EC2 インスタンスを1台起動する。AWS CLI はリソースを作ったアカウントとリージョンを使う。

   ```sh
   make -C infra/terraform start
   ```

   CloudShell などからは `bash bin/start-fleet.sh` でも実行できる。起動時に必要なのは Bash、`jq`、S3 Files に対応する AWS CLI。プロジェクト名が既定の `mycomfy` と異なる環境では、`MYCOMFY_PROJECT` にプロジェクト名を指定する。

   スクリプトは起動テンプレートのタグと利用可能なマウントターゲットを AWS API から取得する。起動したインスタンスの ID は応答の `Instances` に入る。
   オンデマンドで起動するには、利用リージョンの `Running On-Demand G and VT instances` クォータに空きが必要。Spot のクォータとは別に管理される。

4. notify-me（LINE）で起動結果を確認する。通知は日本語で、時刻は JST。初回セットアップに失敗したときは通知に工程名が入り、詳細はインスタンス内の `/var/log/mycomfy/install.log` に残る。自己チェックの結果は `/var/log/mycomfy/boot-check.json` で確認できる。
5. 用が済んだらインスタンスを終了する。Terraform で管理しているリソースも不要なら `terraform destroy` を実行する。

既存環境でセキュリティグループの送信ルールを独立した Terraform リソースに切り替えるときは、AWS 上の同じルールを対応するリソースにインポートしてから plan を確認する。既存の HTTPS や S3 Files 用のルールを再作成する必要はない。
