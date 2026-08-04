from __future__ import annotations

import asyncio
import errno
import fcntl
import os
import socket
import stat
import struct
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any, Protocol

from agentmeter_host.control.events import ControlEvent, EventBroker
from agentmeter_host.ipc.protocol import (
    MAXIMUM_IPC_LINE_BYTES,
    IpcCommandError,
    IpcProtocolError,
    IpcRequest,
    decode_request,
    encode_error,
    encode_event,
    encode_result,
    result_type,
)


class ControlApi(Protocol):
    events: EventBroker

    async def handle_ipc(self, request: IpcRequest) -> dict[str, Any]: ...


def default_ipc_path(
    *,
    uid: int | None = None,
    temporary_directory: str | None = None,
) -> Path:
    active_uid = os.getuid() if uid is None else uid
    root = tempfile.gettempdir() if temporary_directory is None else temporary_directory
    return Path(root) / f"agentmeter-{active_uid}" / "bridge.sock"


def current_peer_uid(peer_socket: Any) -> int:
    getpeereid = getattr(peer_socket, "getpeereid", None)
    if getpeereid is not None:
        return int(getpeereid()[0])
    if hasattr(socket, "LOCAL_PEERCRED"):
        credentials = peer_socket.getsockopt(0, socket.LOCAL_PEERCRED, 256)
        version, uid = struct.unpack_from("=II", credentials)
        if version != 0:
            raise OSError("unsupported local peer credential version")
        return int(uid)
    credentials = peer_socket.getsockopt(
        socket.SOL_SOCKET,
        socket.SO_PEERCRED,
        struct.calcsize("3i"),
    )
    _pid, uid, _gid = struct.unpack("3i", credentials)
    return int(uid)


class _ClientSession:
    def __init__(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        *,
        api: ControlApi,
    ) -> None:
        self.reader = reader
        self.writer = writer
        self.api = api
        self.write_lock = asyncio.Lock()
        self.event_task: asyncio.Task[None] | None = None

    async def run(self) -> None:
        try:
            while not self.reader.at_eof():
                try:
                    line = await self.reader.readline()
                except (ValueError, asyncio.LimitOverrunError):
                    await self.write(
                        encode_error(
                            "invalid",
                            "lineTooLarge",
                            "IPC request exceeds 65536 bytes",
                            recoverable=False,
                        )
                    )
                    return
                if not line:
                    return
                await self.handle_line(line)
        finally:
            if self.event_task is not None:
                self.event_task.cancel()
                await asyncio.gather(self.event_task, return_exceptions=True)
            self.writer.close()
            await self.writer.wait_closed()

    async def handle_line(self, line: bytes) -> None:
        request_id = "invalid"
        try:
            request = decode_request(line)
            request_id = request.id
            if request.type == "events.subscribe":
                if request.payload:
                    raise IpcProtocolError(
                        "invalidPayload", "events.subscribe payload must be empty"
                    )
                if self.event_task is None or self.event_task.done():
                    stream = self.api.events.subscribe()
                    self.event_task = asyncio.create_task(self.stream_events(stream))
                await self.write(encode_result(request.id, "events.subscribed", {}))
                return
            payload = await self.api.handle_ipc(request)
            await self.write(encode_result(request.id, result_type(request.type), payload))
        except IpcProtocolError as error:
            await self.write(encode_error(request_id, error.code, str(error)))
        except IpcCommandError as error:
            await self.write(
                encode_error(
                    request_id,
                    error.code,
                    str(error),
                    recoverable=error.recoverable,
                )
            )
        except Exception:
            await self.write(
                encode_error(
                    request_id,
                    "internalError",
                    "The bridge could not complete the request",
                )
            )

    async def stream_events(self, stream) -> None:
        try:
            async for event in stream:
                await self.write(self._encode_control_event(event))
        finally:
            close = getattr(stream, "aclose", None)
            if close is not None:
                await close()

    @staticmethod
    def _encode_control_event(event: ControlEvent) -> bytes:
        return encode_event(event.sequence, event.type, event.payload)

    async def write(self, data: bytes) -> None:
        async with self.write_lock:
            self.writer.write(data)
            await asyncio.wait_for(self.writer.drain(), timeout=2)


class IpcServer:
    def __init__(
        self,
        path: Path,
        *,
        api: ControlApi,
        current_uid: Callable[[], int] = os.getuid,
        peer_uid: Callable[[Any], int] = current_peer_uid,
    ) -> None:
        self.path = path
        self._api = api
        self._current_uid = current_uid
        self._peer_uid = peer_uid
        self._server: asyncio.AbstractServer | None = None
        self._sessions: set[asyncio.Task[None]] = set()
        self._maximum_clients = 8
        self._socket_identity: tuple[int, int] | None = None
        self._lock_descriptor: int | None = None

    async def start(self) -> None:
        if self._server is not None:
            return
        if len(os.fsencode(self.path)) > 100:
            raise ValueError("IPC socket path must not exceed 100 bytes")
        uid = self._current_uid()
        self._prepare_parent(uid)
        self._acquire_single_instance_lock(uid)
        try:
            if self.path.exists() or self.path.is_symlink():
                existing = self.path.lstat()
                if existing.st_uid != uid or not stat.S_ISSOCK(existing.st_mode):
                    raise PermissionError(f"refusing to replace unsafe IPC path {self.path}")
                if await self._has_active_listener():
                    raise OSError(
                        errno.EADDRINUSE,
                        f"AgentMeter bridge is already running at {self.path}",
                    )
                self.path.unlink()
            self._server = await asyncio.start_unix_server(
                self._accept,
                path=self.path,
                limit=MAXIMUM_IPC_LINE_BYTES + 1,
            )
            os.chmod(self.path, 0o600)
            metadata = self.path.lstat()
            self._socket_identity = (metadata.st_dev, metadata.st_ino)
        except BaseException:
            self._release_single_instance_lock()
            raise

    def _prepare_parent(self, uid: int) -> None:
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        metadata = self.path.parent.lstat()
        if metadata.st_uid != uid or not stat.S_ISDIR(metadata.st_mode):
            raise PermissionError(f"unsafe IPC directory {self.path.parent}")
        os.chmod(self.path.parent, 0o700)

    def _acquire_single_instance_lock(self, uid: int) -> None:
        lock_path = self.path.with_name(f"{self.path.name}.lock")
        flags = os.O_CREAT | os.O_RDWR
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(lock_path, flags, 0o600)
        try:
            metadata = os.fstat(descriptor)
            if metadata.st_uid != uid or not stat.S_ISREG(metadata.st_mode):
                raise PermissionError(f"unsafe IPC lock {lock_path}")
            os.fchmod(descriptor, 0o600)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise OSError(
                    errno.EADDRINUSE,
                    f"AgentMeter bridge is already running at {self.path}",
                ) from error
        except BaseException:
            os.close(descriptor)
            raise
        self._lock_descriptor = descriptor

    async def _has_active_listener(self) -> bool:
        try:
            _reader, writer = await asyncio.wait_for(
                asyncio.open_unix_connection(self.path),
                timeout=0.25,
            )
        except (TimeoutError, OSError):
            return False
        writer.close()
        await writer.wait_closed()
        return True

    def _release_single_instance_lock(self) -> None:
        descriptor = self._lock_descriptor
        self._lock_descriptor = None
        if descriptor is None:
            return
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)

    async def _accept(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        peer_socket = writer.get_extra_info("socket")
        try:
            if (
                len(self._sessions) >= self._maximum_clients
                or peer_socket is None
                or self._peer_uid(peer_socket) != self._current_uid()
            ):
                writer.close()
                await writer.wait_closed()
                return
        except (AttributeError, OSError, TypeError, ValueError):
            writer.close()
            await writer.wait_closed()
            return
        task = asyncio.create_task(_ClientSession(reader, writer, api=self._api).run())
        self._sessions.add(task)
        task.add_done_callback(self._sessions.discard)

    async def close(self) -> None:
        server = self._server
        self._server = None
        if server is not None:
            server.close()
            await server.wait_closed()
        for task in tuple(self._sessions):
            task.cancel()
        if self._sessions:
            await asyncio.gather(*self._sessions, return_exceptions=True)
        self._sessions.clear()
        try:
            metadata = self.path.lstat()
        except FileNotFoundError:
            self._socket_identity = None
            self._release_single_instance_lock()
            return
        identity = (metadata.st_dev, metadata.st_ino)
        if (
            identity == self._socket_identity
            and metadata.st_uid == self._current_uid()
            and stat.S_ISSOCK(metadata.st_mode)
        ):
            self.path.unlink()
        self._socket_identity = None
        self._release_single_instance_lock()
