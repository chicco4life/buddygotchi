from gen import *
# T1: main agent asks; a subagent's end must not clear it
run("t1-main-ask-subagent-end", [h("SessionStart"), h("UserPromptSubmit", prompt="x"),
    pre("Agent","m1"), pre("Bash","m2"), perm("Bash"), note("permission_prompt"),
    pre("Read","r1",agent="a1"), post("Read","r1",agent="a1"), sstop("a1"),
    post("Agent","m1"), wait(20000), pre("Bash","m3") ])
# T2: Notification-only request; subagent end must not clear it
run("t2-anyone-subagent-end", [h("SessionStart"), h("UserPromptSubmit", prompt="x"),
    pre("Agent","m1"), pre("Read","r1",agent="a1"), note("permission_prompt"), wait(8000), sstop("a1"), wait(5000), h("Stop")])
# T3: idle session: subagent end stays idle, even an hour later
run("t3-idle-subagent-end", [h("SessionStart"), h("UserPromptSubmit", prompt="x"), h("Stop"), wait(30000), sstop("a1"), wait(3600000), sstop("a2")])
# T5: StopFailure with agent_id while main asks
run("t5-subagent-stopfailure", [h("SessionStart"), h("UserPromptSubmit", prompt="x"),
    pre("Agent","m1"), pre("Bash","m2"), perm("Bash"), h("StopFailure", agent_id="a1", agent_type="x", error="rate_limit"), wait(3000), post("Bash","m2")])
# T6: two subagents ask; a1 ends -> a2 still asks with a new id
run("t6-two-askers", [h("SessionStart"), h("UserPromptSubmit", prompt="x"), pre("Agent","m1"), pre("Agent","m2"),
    pre("Bash","b1",agent="a1"), perm("Bash",agent="a1"), pre("Bash","b2",agent="a2"), perm("Bash",agent="a2"),
    sstop("a1"), wait(2000), post("Bash","b2",agent="a2"), sstop("a2"), post("Agent","m1"), post("Agent","m2"), h("Stop")])
