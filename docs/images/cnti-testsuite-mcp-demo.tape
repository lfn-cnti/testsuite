# Recording of docs/images/cnti-testsuite-mcp-demo.gif with https://github.com/charmbracelet/vhs.
# The published GIF is made from the frames (Output frames/) with the idle waits cut.
# A real Claude Code session driving `cnti-testsuite mcp --allow-install` against
# sample-cnfs/sample-mcp-demo on a kind cluster. Needs cnti-testsuite on PATH,
# KUBECONFIG set, setup done, the demo's chart/ in the working directory, the server
# registered (`claude mcp add cnti -- cnti-testsuite mcp --allow-install`), and the
# suite's tools allowed in .claude/settings.local.json so the recording runs
# unattended (an interactive session asks before each tool call instead).
# Set DEMO_DIR to that directory before running vhs. IS_DEMO=1 and CLAUDE_CODE_HIDE_CWD=1
# keep the account and the local path off the recording.
# Six prompts in one session, each followed by a Sleep long enough for the agent to finish. The
# directory starts with the chart only: the first prompt has the agent write cnti-testsuite.yaml.
# It plays in real time; in the published GIF the idle stretch after each answer is cut to a
# short pause.
Output cnti-testsuite-mcp-demo.gif
Set Shell "bash"
Set FontFamily "Nimbus Mono PS"
Set FontSize 17
Set LineHeight 1.15
Set Width 1300
Set Height 760
Set Padding 24
Set Theme "Dracula"
Set TypingSpeed 40ms
Set Framerate 8
Set PlaybackSpeed 1

Hide
Type "cd $DEMO_DIR && export PS1='$ ' IS_DEMO=1 CLAUDE_CODE_HIDE_CWD=1"
Enter
# The first start in a new directory asks whether to trust it: accepted here, off camera.
Type "claude"
Enter
Sleep 6s
Enter
Sleep 4s
Type "/exit"
Sleep 500ms
Enter
Sleep 2s
Type "clear"
Enter
Sleep 1s
Show

Type "ls; grep -A2 Probe chart/values.yaml"
Enter
Sleep 3s
Type "claude"
Enter
Sleep 6s

# 1. Write the configuration for the chart, and check it.
Type "Write a cnti-testsuite.yaml for the Helm chart in chart/ and check it with the suite."
Sleep 1s
Enter
Sleep 75s

# 2. Install the CNF and run the probe tests.
Type "Install the CNF and run the liveness and readiness tests."
Sleep 1s
Enter
Sleep 90s

# 3. Fix what failed, in the Helm chart itself.
Type "Fix the failures directly in the Helm chart. Don't reinstall yet."
Sleep 1s
Enter
Sleep 50s

# 4. Reinstall and run the tests again.
Type "Reinstall the CNF and run both tests again."
Sleep 1s
Enter
Sleep 90s

# 5. The results, now passing.
Type "Show me the results of both tests."
Sleep 1s
Enter
Sleep 40s

# 6. What changed in the chart.
Type "Show me how you changed the chart."
Sleep 1s
Enter
Sleep 40s

Type "/exit"
Sleep 500ms
Enter
Sleep 3s
