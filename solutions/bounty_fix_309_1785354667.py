# Default behavior for all files: auto-detect text files and normalize line endings to LF in Git repository
* text=auto

# Ensure shell scripts always maintain LF line endings (required for Unix execution)
*.sh text eol=lf
*.bash text eol=lf

# Ensure Windows scripts maintain CRLF line endings (required for CMD/PowerShell execution)
*.bat text eol=crlf
*.cmd text eol=crlf
*.ps1 text eol=crlf

# Binary assets - explicitly mark as binary to prevent line ending conversion
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.ico binary
*.webp binary
*.pdf binary
*.zip binary
*.tar.gz binary
*.gz binary
*.7z binary
*.woff binary
*.woff2 binary
*.ttf binary
*.eot binary