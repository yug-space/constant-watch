import argparse
import asyncio
import json
import os
import sys


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="Local screen memory for macOS and Windows")
    parser.add_argument("command", choices=["serve", "mcp", "doctor", "permissions", "rebuild"])
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if args.command == "serve":
        import uvicorn
        from .server import create_app
        uvicorn.run(create_app(), host="127.0.0.1", port=args.port, access_log=False)
    elif args.command == "mcp":
        from .mcp_server import create_mcp
        create_mcp().run(transport="stdio")
    elif args.command == "rebuild":
        from .store import Store
        from .config import data_dir
        Store(data_dir()).rebuild_exports()
        print("Markdown journals rebuilt.")
    else:
        from .capture import native
        from .config import data_dir, load_settings
        from .model import LocalModel

        async def check():
            try:
                permissions = await native("permissions" if args.command == "permissions" else "status")
            except Exception as exc:
                permissions = {"error": str(exc)}
            root = data_dir()
            print(json.dumps({"permissions": permissions, "model": await LocalModel().status(load_settings(root).model), "data_directory": str(root)}, indent=2))
        asyncio.run(check())


if __name__ == "__main__":
    main()
