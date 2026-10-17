#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Setting up Vercel environment for Flutter..."

# 1. Download and extract the Flutter SDK if not already present
if [ ! -d "flutter" ]; then
  echo "Downloading Flutter SDK..."
  git clone https://github.com/flutter/flutter.git -b stable
fi

export PATH="$PATH:`pwd`/flutter/bin"

# 2. Generate the .env file from Vercel's environment variables
echo "Generating .env file..."
cat << EOF > .env
SUPABASE_URL=$SUPABASE_URL
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
EOF

# 3. Generate Freezed & Riverpod code
echo "Generating code with build_runner..."
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 4. Build the Flutter web app
echo "Building Flutter web app..."
flutter build web --release

echo "Build complete!"
