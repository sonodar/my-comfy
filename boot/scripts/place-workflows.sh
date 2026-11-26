#!/usr/bin/env bash
# ワークフローの配置：S3 の config/workflows/ を取得し、台本生成プロンプトを注入して配置する。
# 台本生成プロンプトは SSM から /etc/mycomfy/script-generation-prompt.txt に
# 置かれたものを使い、ワークフロー内のプレースホルダ文字列と置き換える。
# 台本生成プロンプトが無い場合はプレースホルダを空文字にし、変換ノードの標準システムプロンプトで動かす。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

mkdir -p /opt/mycomfy/workflows /opt/ComfyUI/user/default/workflows
aws s3 cp "s3://$BUCKET_NAME/config/workflows/" /opt/mycomfy/workflows/ --recursive >/dev/null

SCRIPT_GENERATION_PROMPT_FILE="/etc/mycomfy/script-generation-prompt.txt"
if [ -s "$SCRIPT_GENERATION_PROMPT_FILE" ]; then
  echo "workflows: 台本生成プロンプトを注入します"
else
  echo "WARN: 台本生成プロンプトが無いため、プロンプト変換は ComfyUI 標準のシステムプロンプトで動きます"
fi

/opt/pytorch/bin/python - "$SCRIPT_GENERATION_PROMPT_FILE" \
  /opt/mycomfy/workflows/api/video-workflow-i2v-basic.json \
  /opt/mycomfy/workflows/ui/video-workflow-i2v-basic.json <<'PYEOF'
import json
import os
import sys

script_generation_prompt = ""
if os.path.isfile(sys.argv[1]):
    with open(sys.argv[1], encoding="utf-8") as f:
        script_generation_prompt = f.read()
placeholder = "__MYCOMFY_SCRIPT_GENERATION_PROMPT__"


def replace(obj):
    if isinstance(obj, str):
        return script_generation_prompt if obj == placeholder else obj
    if isinstance(obj, list):
        return [replace(v) for v in obj]
    if isinstance(obj, dict):
        return {k: replace(v) for k, v in obj.items()}
    return obj


for path in sys.argv[2:]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(replace(data), f, ensure_ascii=False, indent=2)
PYEOF

cp /opt/mycomfy/workflows/ui/*.json /opt/ComfyUI/user/default/workflows/
echo "workflows: 配置完了"
