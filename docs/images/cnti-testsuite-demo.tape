# Recording of docs/images/cnti-testsuite-demo.gif with https://github.com/charmbracelet/vhs.
# Needs cnti-testsuite on PATH, KUBECONFIG set, setup done, the tests' tools installed,
# and the CoreDNS example config as ./cnti-testsuite.yaml. The Hide/Show pair cuts
# the wait for the CNF to become ready.
Output cnti-testsuite-demo.gif
Set Shell "bash"
Set FontFamily "Nimbus Mono PS"
Set FontSize 19
Set LineHeight 1.15
Set Width 1200
Set Height 500
Set Padding 24
Set Theme "Dracula"
Set TypingSpeed 55ms
Set Framerate 15
Set PlaybackSpeed 1.6

Hide
Type "export PS1='$ ' && clear"
Enter
Sleep 1s
Show

Type "cnti-testsuite cnf_install --cnf-config ./cnti-testsuite.yaml"
Sleep 500ms
Enter
Sleep 4s
Hide
Sleep 18s
Show
Sleep 2s

Type "cnti-testsuite latest_tag hostport_not_used cpu_limits seccomp_profile"
Sleep 500ms
Enter
Sleep 13s
Sleep 10s
