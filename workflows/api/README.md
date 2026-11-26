# workflows/api

実行用ワークフロー（API 形式 JSON）を置く。

- `video-workflow-i2v-basic.json`：開始画像＋自然文から動画を生成する。自然文は ComfyUI コアノード（`TextGenerateLTX2Prompt`）が、テキストエンコーダのモデルを流用して台本へ変換してからエンコードへ渡る。台本生成プロンプトはプレースホルダで置き、起動時の配置で SSM から取得した本文に置き換える。ノード構成は ComfyUI 本体同梱のノードのみで組み、シグマと CFG は配布元のワークフローに合わせた。生成物は ComfyUI の出力先（インスタンス内）に保存される。
