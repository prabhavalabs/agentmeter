"""Private local IPC for the AgentMeter desktop application."""

from agentmeter_host.ipc.protocol import (
    IpcCommandError,
    IpcProtocolError,
    IpcRequest,
    decode_request,
    encode_error,
    encode_event,
    encode_result,
)
from agentmeter_host.ipc.server import IpcServer, default_ipc_path

__all__ = [
    "IpcCommandError",
    "IpcProtocolError",
    "IpcRequest",
    "IpcServer",
    "decode_request",
    "default_ipc_path",
    "encode_error",
    "encode_event",
    "encode_result",
]
