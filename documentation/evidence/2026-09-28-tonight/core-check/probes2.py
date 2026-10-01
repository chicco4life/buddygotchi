from gen import *
base = [h("SessionStart"), h("UserPromptSubmit", prompt="x"), pre("Agent","m0"), pre("Bash","m1"), pre("Bash","b1",agent="a1")]
run("h1-hook-right-after-clear", base + [perm("Bash"), note("permission_prompt"), post("Bash","m1"), perm("Bash",agent="a1"), note("permission_prompt"), wait(3000), post("Bash","b1",agent="a1")], states=True)
run("h2-notice-first-after-clear", base + [perm("Bash"), note("permission_prompt"), post("Bash","m1"), note("permission_prompt"), perm("Bash",agent="a1"), wait(3000), post("Bash","b1",agent="a1")], states=True)
run("h4-elicitation-parallel-read", [h("SessionStart"), h("UserPromptSubmit", prompt="x"), pre("mcp__x__ask","e1"), pre("Read","r1"),
    h("Elicitation", mcp_server_name="x", message="m"), note("elicitation_dialog"), post("Read","r1"), wait(10000), h("ElicitationResult", mcp_server_name="x", action="accept")], states=True)
