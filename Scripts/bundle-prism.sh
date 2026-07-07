#!/bin/bash
# Scripts/bundle-prism.sh
#
# Downloads and bundles Prism.js with language definitions into a single JavaScript file.
#
# Default mode ("verify"): downloads Prism core and every language, checks each downloaded
# file's SHA-256 against Scripts/prism-checksums.sha256, and fails hard (exit 1) on any
# mismatch or any missing/failed download. Nothing is written to the committed bundle path
# unless every file downloads and verifies successfully.
#
# --record mode: downloads everything, (re)writes Scripts/prism-checksums.sha256 from what
# was just fetched, then bundles. Recorded hashes are only as trustworthy as this run's
# network — use this only when intentionally bumping PRISM_VERSION or adding a language, and
# commit the manifest and the bundle together.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$PROJECT_ROOT/Sources/RemodexTextKit/Internal/Highlighter/Prism"
OUTPUT_FILE="$RESOURCES_DIR/prism-bundle.js"
CHECKSUM_FILE="$SCRIPT_DIR/prism-checksums.sha256"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

MODE="verify"
if [ "$1" = "--record" ]; then
  MODE="record"
fi

if [ "$MODE" = "record" ]; then
  echo "📦 Bundling Prism.js and language definitions (RECORD mode)..."
  echo "⚠️  Recorded hashes are only as trustworthy as this run's network. Only use --record"
  echo "⚠️  when intentionally bumping PRISM_VERSION or adding a language, and commit the"
  echo "⚠️  manifest and the bundle together."
else
  echo "📦 Bundling Prism.js and language definitions (verify mode)..."
fi

# Prism CDN base URL (minified files)
PRISM_VERSION="1.29.0"
PRISM_CDN="https://cdnjs.cloudflare.com/ajax/libs/prism/$PRISM_VERSION"

# Core Prism (required)
PRISM_CORE="$PRISM_CDN/prism.min.js"

# Language definitions to include
# See: https://prismjs.com/#supported-languages
LANGUAGES=(
  # Web fundamentals
  "markup"          # HTML, XML, SVG
  "markup-templating"
  "css"
  "scss"
  "sass"
  "less"
  "javascript"
  "typescript"
  "jsx"
  "tsx"

  # Systems programming
  "clike"           # C-like (required for many languages)
  "c"
  "cpp"
  "rust"
  "go"
  "zig"

  # Apple ecosystem
  "swift"
  "objectivec"

  # JVM languages
  "java"
  "kotlin"
  "scala"
  "groovy"

  # .NET ecosystem
  "csharp"
  "fsharp"

  # Scripting languages
  "python"
  "ruby"
  "php"
  "perl"
  "lua"

  # Functional languages
  "elixir"
  "erlang"
  "haskell"
  "ocaml"
  "reason"

  # Modern languages
  "dart"
  "crystal"

  # Shell & system
  "bash"
  "powershell"

  # Data & config
  "json"
  "yaml"
  "toml"
  "sql"

  # Markup & docs
  "markdown"
  "latex"

  # Web assembly & GPU
  "wasm"
  "wgsl"

  # Query languages
  "graphql"
  "sparql"

  # Other
  "diff"
  "git"
  "http"
  "regex"
  "docker"
  "nginx"
)

# Create resources directory if it doesn't exist
mkdir -p "$RESOURCES_DIR"
DOWNLOAD_DIR="$TEMP_DIR/downloads"
mkdir -p "$DOWNLOAD_DIR"

if [ "$MODE" = "verify" ] && [ ! -f "$CHECKSUM_FILE" ]; then
  echo "❌ Checksum manifest not found: $CHECKSUM_FILE"
  echo "   Run './Scripts/bundle-prism.sh --record' to create it (requires network access)."
  exit 1
fi

# Download a single file into $DOWNLOAD_DIR, failing hard on any error.
# In verify mode, also checks the SHA-256 against the manifest.
download_and_verify() {
  local url="$1"
  local filename="$2"
  local dest="$DOWNLOAD_DIR/$filename"

  if ! curl -sS -f "$url" -o "$dest"; then
    echo "❌ Failed to download $filename from $url"
    exit 1
  fi

  if [ "$MODE" = "verify" ]; then
    local actual_hash
    actual_hash=$(shasum -a 256 "$dest" | awk '{print $1}')
    local expected_hash
    expected_hash=$(grep -E "  $filename\$" "$CHECKSUM_FILE" | awk '{print $1}')

    if [ -z "$expected_hash" ]; then
      echo "❌ No checksum entry found for $filename in $CHECKSUM_FILE"
      exit 1
    fi

    if [ "$actual_hash" != "$expected_hash" ]; then
      echo "❌ Checksum mismatch for $filename"
      echo "   expected: $expected_hash"
      echo "   actual:   $actual_hash"
      exit 1
    fi
  fi
}

# Download and verify Prism core
echo "⬇️  Downloading Prism core..."
download_and_verify "$PRISM_CORE" "prism.min.js"

# Download and verify each language (no silent skipping on 404 in either mode)
for lang in "${LANGUAGES[@]}"; do
  # Skip comments
  [[ "$lang" =~ ^#.*$ ]] && continue

  echo "⬇️  Downloading language: $lang"
  LANG_URL="$PRISM_CDN/components/prism-$lang.min.js"
  download_and_verify "$LANG_URL" "prism-$lang.min.js"
done

if [ "$MODE" = "record" ]; then
  echo "📝 Writing checksum manifest..."
  {
    shasum -a 256 "$DOWNLOAD_DIR/prism.min.js" | sed "s#$DOWNLOAD_DIR/##"
    for lang in "${LANGUAGES[@]}"; do
      [[ "$lang" =~ ^#.*$ ]] && continue
      shasum -a 256 "$DOWNLOAD_DIR/prism-$lang.min.js" | sed "s#$DOWNLOAD_DIR/##"
    done
  } > "$CHECKSUM_FILE"
fi

# Assemble the bundle from the verified downloads
BUNDLE="$TEMP_DIR/bundle.js"
echo "// Prism.js v$PRISM_VERSION - Bundled on $(date)" > "$BUNDLE"
echo "// Auto-generated by Scripts/bundle-prism.sh - DO NOT EDIT" >> "$BUNDLE"
echo "" >> "$BUNDLE"

cat "$DOWNLOAD_DIR/prism.min.js" >> "$BUNDLE"
echo "" >> "$BUNDLE"

SUCCESS_COUNT=0
for lang in "${LANGUAGES[@]}"; do
  [[ "$lang" =~ ^#.*$ ]] && continue
  cat "$DOWNLOAD_DIR/prism-$lang.min.js" >> "$BUNDLE"
  echo "" >> "$BUNDLE"
  ((SUCCESS_COUNT++))
done

# Add helper function for token flattening
cat >> "$BUNDLE" << 'EOF'

// Helper function to flatten Prism tokens into simple objects
function flattenPrismTokens(tokens) {
  var result = [];

  function flatten(token, parentType) {
    if (typeof token === 'string') {
      if (token.length > 0) {
        result.push({ content: token, type: parentType || 'plain' });
      }
    } else if (Array.isArray(token)) {
      token.forEach(function(t) { flatten(t, parentType); });
    } else if (token && typeof token === 'object') {
      var type = token.type || parentType || 'plain';
      if (typeof token.content === 'string') {
        if (token.content.length > 0) {
          result.push({ content: token.content, type: type });
        }
      } else if (Array.isArray(token.content)) {
        token.content.forEach(function(t) { flatten(t, type); });
      } else if (token.content && typeof token.content === 'object') {
        flatten(token.content, type);
      }
    }
  }

  tokens.forEach(function(token) { flatten(token, null); });
  return result;
}

// Export tokenization function
function tokenizeCode(code, language) {
  try {
    var grammar = Prism.languages[language];
    if (!grammar) {
      return [{ content: code, type: 'plain' }];
    }
    var tokens = Prism.tokenize(code, grammar);
    return flattenPrismTokens(tokens);
  } catch (e) {
    return [{ content: code, type: 'plain' }];
  }
}
EOF

# Move to final location only on full success
mv "$BUNDLE" "$OUTPUT_FILE"

# Report size
SIZE=$(wc -c < "$OUTPUT_FILE" | xargs)
SIZE_KB=$((SIZE / 1024))

echo ""
echo "✅ Bundle created: $OUTPUT_FILE"
echo "📊 Bundle size: ${SIZE_KB}KB"
echo "📊 Languages downloaded: $SUCCESS_COUNT"
echo ""
if [ "$MODE" = "record" ]; then
  echo "🎉 Done! Commit the updated manifest ($CHECKSUM_FILE) and bundle together."
else
  echo "🎉 Done! The bundle is ready to be committed to the repository."
fi
