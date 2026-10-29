#!/usr/bin/env bash
# Downloads the free (SIL Open Font License) fonts the bundled book designs ask for.
# Usage: tools/fetch-book-fonts.sh [DIR]   (default: ~/Library/Fonts on a Mac, ./fonts elsewhere)
# Designs fall back to Libertinus Serif (built into Typst) when a font is missing, so this is optional.
set -euo pipefail
if [[ $# -gt 0 ]]; then dir="$1"; elif [[ "$(uname)" == Darwin ]]; then dir="$HOME/Library/Fonts"; else dir="fonts"; fi
mkdir -p "$dir"
base="https://raw.githubusercontent.com/google/fonts/main/ofl"
fonts=(
  "ebgaramond/EBGaramond[wght].ttf"
  "ebgaramond/EBGaramond-Italic[wght].ttf"
  "imfellenglish/IMFeENrm28P.ttf"
  "imfellenglish/IMFeENit28P.ttf"
  "imfellenglishsc/IMFeENsc28P.ttf"
  "sourceserif4/SourceSerif4[opsz,wght].ttf"
  "sourceserif4/SourceSerif4-Italic[opsz,wght].ttf"
  "sourcesans3/SourceSans3[wght].ttf"
  "notosanssymbols/NotoSansSymbols[wght].ttf"
  "notosanssymbols2/NotoSansSymbols2-Regular.ttf"
)
for f in "${fonts[@]}"; do
  name="$(basename "$f")"
  url="$base/$(echo "$f" | sed 's/\[/%5B/g; s/\]/%5D/g')"
  if [[ -f "$dir/$name" ]]; then echo "have $name"; continue; fi
  curl -fsSL "$url" -o "$dir/$name" && echo "got  $name"
done
echo "fonts in $dir"
