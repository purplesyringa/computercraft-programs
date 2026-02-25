import math
import string

valid_identifier_chars = set(string.digits + string.ascii_letters + "_")
reserved_words = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "global", "goto",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}

def serialize(obj) -> bytes:
    if isinstance(obj, (int, float)):
        return str(obj).encode()
    elif isinstance(obj, str):
        return serialize(obj.encode())
    elif isinstance(obj, (bytes, bytearray)):
        if b"\\" not in obj and b"\n" not in obj and b"\r" not in obj:
            if b"\"" not in obj:
                return b'"' + obj + b'"'
            elif b"'" not in obj:
                return b"'" + obj + b"'"
        prefix, suffix = b"", b""
        if b"\r" in obj:
            char_counts = [0] * 256
            for c in obj:
                char_counts[c] += 1
            for c in b'^$()%.[]*+-?"\r\\':
                char_counts[c] = math.inf
            escape = min(range(256), key = lambda c: char_counts[c])
            escape_s = bytes([escape])
            if char_counts[escape] == 0:
                obj = obj.replace(b"\r", escape_s)
                prefix = b'('
                suffix = b'):gsub("E","\\r")'.replace(b"E", escape_s)
            else:
                obj = obj.replace(escape_s, escape_s + b"]").replace(b"\r", escape_s + b"r")
                prefix = b'('
                suffix = b'):gsub("Er","\\r"):gsub("E]","E")'.replace(b"E", escape_s)
        level = 0
        # Somewhat surprisingly, Lua forbids even opening brackets inside brackets.
        while b"[" + b"=" * level + b"[" in obj or b"]" + b"=" * level + b"]" in obj:
            level = level + 1
        if obj.startswith(b"\n"):
            obj = b"\n" + obj
        return prefix + b"[" + b"=" * level + b"[" + obj + b"]" + b"=" * level + b"]" + suffix
    elif isinstance(obj, list):
        if not obj:
            return b"{}"
        return b"{" + b",".join(map(serialize, obj)) + b"}"
    elif isinstance(obj, dict):
        if not obj:
            return b"{}"
        return b"{" + b",".join(
            serialize_key(k) + b"=" + serialize(v)
            for k, v in obj.items()
        ) + b"}"
    else:
        raise TypeError(f"Cannot serialize type {type(obj).__name__}")


def serialize_key(obj) -> bytes:
    if isinstance(obj, (bytes, bytearray)):
        try:
            obj = obj.decode()
        except UnicodeDecodeError:
            return b"[" + serialize(obj) + b"]"
    if (
        isinstance(obj, str)
        and obj
        and all(c in valid_identifier_chars for c in obj)
        and not obj[0].isdigit()
        and obj not in reserved_words
    ):
        return obj.encode()
    return b"[" + serialize(obj) + b"]"
