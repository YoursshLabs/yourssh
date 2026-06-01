# AI Chat

An AI assistant sidebar that you can open alongside any terminal session.

<!-- SCREENSHOT: Terminal with the AI Chat sidebar open on the right, showing a conversation with a command suggestion and a tool result -->

## Opening the Sidebar

Click the **AI** button in the session toolbar (or press the configured hotkey). The sidebar slides in without resizing the terminal pane.

## Supported Providers

| Provider | Models available |
|---|---|
| **Anthropic Claude** | claude-opus-4-8, claude-sonnet-4-6, claude-haiku-4-5, and others |
| **OpenAI** | gpt-4o, gpt-4o-mini, and others |
| **Google Gemini** | gemini-2.0-flash, gemini-1.5-pro, and others |

Configure API keys and default model in **Settings → AI**.

## Tool Calling

The AI can call tools to help you:

| Tool | What it does |
|---|---|
| `exec_command` | Runs a shell command on the active session and returns the output |
| `read_file` | Reads a remote file via SFTP |
| `list_directory` | Lists a remote directory |

Tool calls are shown inline in the conversation with the command and output.

## Tips

- Paste error output into the chat and ask "what does this mean?"
- Ask "how do I restart nginx on this system?" — the AI can exec the command for you.
- Use the model selector in the sidebar header to switch models mid-conversation.

## Related Pages

- [Settings](User-Guide-Settings) — configure API keys and default model
- [Terminal](User-Guide-Terminal) — the AI sidebar is opened from the terminal toolbar
