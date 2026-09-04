Output docs/sarus-suite-demo.gif

Set FontSize 18
Set Width 1000
Set Height 560
Set TypingSpeed 35ms
Set Padding 24
Set WindowBar Colorful

Type "VERSION=v26.8.3"
Enter
Type "ARCH=arm64"
Enter
Sleep 1s
Type "ls sarus-suite-${VERSION}-${ARCH}.tar.gz"
Enter
Sleep 1s
Type "tar -xzf sarus-suite-${VERSION}-${ARCH}.tar.gz"
Enter
Sleep 1s
Type "cd sarus-suite"
Enter
Sleep 1s
Type "ls -l examples/"
Enter
Sleep 1s
Type "./bin/sarus-suite-shell -- sarusctl run examples/ubuntu.toml cat /etc/os-release"
Enter
Sleep 5s
Type "./bin/sarus-suite-shell -- sarusctl run examples/debian.toml cat /etc/os-release"
Enter
Sleep 5s
