#!/usr/bin/env bash

set -e

OUTPUT="media.json"

echo "[" > $OUTPUT
FIRST=true

add_entry () {
  local FILEPATH="$1"
  local TYPE="$2"

  FILENAME=$(basename "$FILEPATH")
  TITLE="${FILENAME%.*}"

  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo "," >> $OUTPUT
  fi

  cat <<EOF >> $OUTPUT
{
  "url": "$FILEPATH",
  "type": "$TYPE",
  "title": "$TITLE"
}
EOF
}

# Videos
for file in video/*; do
  [ -f "$file" ] || continue
  case "$file" in
    *.mp4|*.webm|*.ogg|*.mov)
      add_entry "$file" "video"
      ;;
  esac
done

# PDFs
for file in pdf/*; do
  [ -f "$file" ] || continue
  case "$file" in
    *.pdf)
      add_entry "$file" "pdf"
      ;;
  esac
done

echo "]" >> $OUTPUT

echo "✅ media.json generated"