from pathlib import Path

path = Path("ChatGPTWebView/Web/ChatGPTConversationMapCapture.swift")
text = path.read_text(encoding="utf-8")
old = """        const parts = Array.isArray(message.content?.parts) ? message.content.parts : [];
        let content = parts.map(renderPart).filter(Boolean).join('\\n\\n');
        if (!content && typeof message.content?.text === 'string') content = message.content.text;
"""
new = """        const contentType = String(message.content?.content_type || '').toLowerCase();
        const parts = Array.isArray(message.content?.parts) ? message.content.parts : [];
        let content = contentType === 'text'
          ? parts.filter(part => typeof part === 'string').join('')
          : parts.map(renderPart).filter(Boolean).join('\\n\\n');
        if (!content && typeof message.content?.text === 'string') content = message.content.text;
"""
count = text.count(old)
if count != 1:
    raise SystemExit(f"Expected one ChatGPT text-part serializer match, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Matched ChatGPT text-part serialization to the shipped frontend")
