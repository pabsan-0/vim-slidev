# Output settings
Output demo.gif

Set FontSize 10
Set Width 800
Set Height 600
Set Padding 8
Set Theme "Catppuccin Frappe"

# Requires vhs of fork (PR Pending)
#   git clone -b caption-overlay https://github.com/pkazmier/vhs  && cd vhs
#   go build .
Set CaptionAlignment "bottom-right"
Set CaptionInactivityTimer 900ms
Set CaptionKeyStyle "vim"


Type "vim presentation.md"
Enter
Sleep 1000ms

CaptionOn

# Enabling the plugin
Type ":SlidevEnable"
Sleep 200ms
Enter
Sleep 1500ms


# Navigation
Ctrl+N Sleep 1000ms
Ctrl+N Sleep 1000ms
Ctrl+N Sleep 1000ms
Ctrl+P Sleep 1000ms
Sleep 1000ms


# Jumping to a slide
Type "\s"
Sleep 1000ms
Type "10"
Sleep 1000ms
Enter
Sleep 2000ms


# Focus
Type "\z" Sleep 1.5s
Ctrl+P Sleep 1000ms
Ctrl+P Sleep 1000ms
Ctrl+P Sleep 3000ms

Type "\z"
Sleep 1.5s


# Focus
Type "\s8" Sleep 1000ms
Enter
Type "6j" Sleep 500ms
Type "\l" Sleep 1000ms
Type "wwwveee" Sleep 1000ms
Type "\l" Sleep 1000ms
Type "\L" Sleep 1000ms
Type "6jciWhttps://sli.dev"
Escape
Sleep 1000ms


# SlidevInfo
# Good for showing plugin status/metadata
Type ":SlidevInfo"
Enter
Sleep 3s

CaptionOff

# Clean up
Type ":q!"
Sleep 100ms
Enter
