# Run tools/record-wizard.sh from the repository root
# This walkthrough discards its draft and declines model removal
Output .github/assets/wizard.gif

Require bash

Set Shell "bash"
Set FontFamily "Menlo"
Set FontSize 21
Set Width 1080
Set Height 780
Set Padding 24
Set WindowBar Colorful
Set Theme "Github"
Set Framerate 12
Set TypingSpeed 80ms

Env TERM "xterm-256color"
Env COLORTERM "truecolor"
Env PS1 "$ "

Hide
Type 'unset NO_COLOR; export PATH="$PARED_DEMO_BIN:$PATH"; pared() { command pared "$@" --policy "$PARED_DEMO_POLICY"; }; clear'
Enter
Sleep 500ms
Show

Type "pared wizard"
Enter
Wait+Screen@10s /What would you like to do/
Sleep 2s
Down
Enter
Wait+Screen@10s /What would you like to change/
Down
Enter
Wait+Screen@10s /Choose features/
Type "/genmoji"
Sleep 1s
Space
Sleep 500ms
Escape
Type "/writing"
Sleep 1s
Space
Enter
Wait+Screen@10s /Review changes/
Sleep 3s
Enter
Sleep 1s
Down 2
Enter
Wait+Screen@10s /Ready to save/
Sleep 2s
Down 2
Enter
Wait+Screen@10s /What would you like to do/
Down 4
Enter
Sleep 4s
Enter
Wait+Screen@10s /What would you like to do/
Up
Enter
Sleep 1s
