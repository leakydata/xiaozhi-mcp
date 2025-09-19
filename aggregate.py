# --- force UTF-8 stdio on Windows ---
import sys, asyncio
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
# ------------------------------------
# For Windows, prefer Selector loop so stdio works predictably
if sys.platform.startswith("win"):
    try:
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    except Exception:
        pass
        
from mcp.server.fastmcp import FastMCP

#python mcp_pipe.py aggregate.py --env-file .env.xiaozhi1

#from tools.conversation_dingtalk import register_conversation_tools
#from tools.email_qq import register_email_tools
#from tools.system import register_system_tools
#from tools.web_webpilot import register_web_tools
from tools.sqlite_tool import register_sqlite_tools

# 创建MCP服务器
mcp = FastMCP("AggregateMCP")

# 注册所有工具
#register_conversation_tools(mcp)
#register_email_tools(mcp)
#register_system_tools(mcp)
#register_web_tools(mcp)
register_sqlite_tools(mcp)


if __name__ == "__main__":
    mcp.run(transport="stdio")
