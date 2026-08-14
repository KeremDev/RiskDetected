export type SupportAttachmentInput = {
  filename?: string;
  mime_type?: string;
  data?: string;
  size_bytes?: number;
};

export type NormalizedSupportAttachment = {
  filename: string;
  mime_type: string;
  data: string;
  size_bytes: number;
};

type AttachmentKind = {
  mimeType: "image/jpeg" | "image/png" | "application/pdf";
  extensions: readonly string[];
  matches: (bytes: Uint8Array) => boolean;
};

const MAX_ATTACHMENT_COUNT = 3;
const MAX_ATTACHMENT_BYTES = 5_000_000;
const MAX_ATTACHMENT_TOTAL_BYTES = 15_000_000;

const ALLOWED_ATTACHMENT_KINDS: readonly AttachmentKind[] = [
  {
    mimeType: "image/jpeg",
    extensions: ["jpg", "jpeg"],
    matches: (bytes) =>
      bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
      bytes[2] === 0xff,
  },
  {
    mimeType: "image/png",
    extensions: ["png"],
    matches: (bytes) =>
      bytes.length >= 8 &&
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every(
        (value, index) => bytes[index] === value,
      ),
  },
  {
    mimeType: "application/pdf",
    extensions: ["pdf"],
    matches: (bytes) =>
      bytes.length >= 5 &&
      [0x25, 0x50, 0x44, 0x46, 0x2d].every(
        (value, index) => bytes[index] === value,
      ),
  },
] as const;

function cleanFilename(value: unknown): string {
  const raw = Array.from(String(value ?? ""), (character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    const isControlCharacter = codePoint <= 0x1f || codePoint === 0x7f;
    const isPathSeparator = character === "/" || character === "\\";
    return isControlCharacter || isPathSeparator ? "_" : character;
  }).join("").trim().slice(0, 120);
  return raw || "ek-dosya";
}

function isValidStandardBase64(value: string): boolean {
  return value.length > 0 && value.length % 4 === 0 &&
    /^[A-Za-z0-9+/]*={0,2}$/.test(value);
}

function decodedBase64ByteLength(base64: string): number {
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return Math.max(0, Math.floor((base64.length * 3) / 4) - padding);
}

function decodeSignaturePrefix(base64: string): Uint8Array | null {
  try {
    const prefix = atob(base64.slice(0, Math.min(base64.length, 64)));
    return Uint8Array.from(prefix, (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

function fileExtension(filename: string): string {
  const index = filename.lastIndexOf(".");
  return index >= 0 ? filename.slice(index + 1).toLowerCase() : "";
}

export function normalizeSupportAttachments(value: unknown): {
  attachments: NormalizedSupportAttachment[];
  error?: { code: string; message: string };
} {
  if (value === undefined || value === null) return { attachments: [] };
  if (!Array.isArray(value)) {
    return {
      attachments: [],
      error: {
        code: "invalid_attachments",
        message: "Ek dosya verisi geçersiz.",
      },
    };
  }
  if (value.length > MAX_ATTACHMENT_COUNT) {
    return {
      attachments: [],
      error: {
        code: "too_many_attachments",
        message: `En fazla ${MAX_ATTACHMENT_COUNT} ek dosya gönderebilirsin.`,
      },
    };
  }

  let totalBytes = 0;
  const attachments: NormalizedSupportAttachment[] = [];
  for (const item of value) {
    const source = item as SupportAttachmentInput;
    const data = typeof source?.data === "string"
      ? source.data.replace(/\s/g, "")
      : "";
    if (!isValidStandardBase64(data)) {
      return {
        attachments: [],
        error: {
          code: "invalid_attachment_data",
          message: "Ek dosya verisi geçersiz.",
        },
      };
    }

    const decodedBytes = decodedBase64ByteLength(data);
    if (decodedBytes > MAX_ATTACHMENT_BYTES) {
      return {
        attachments: [],
        error: {
          code: "attachment_too_large",
          message: "Ek dosya 5 MB'dan küçük olmalı.",
        },
      };
    }

    totalBytes += decodedBytes;
    if (totalBytes > MAX_ATTACHMENT_TOTAL_BYTES) {
      return {
        attachments: [],
        error: {
          code: "attachments_too_large",
          message: "Ek dosyaların toplam boyutu çok büyük.",
        },
      };
    }

    const filename = cleanFilename(source.filename);
    const claimedMimeType = String(source.mime_type ?? "").trim().toLowerCase();
    const signature = decodeSignaturePrefix(data);
    const detectedKind = signature
      ? ALLOWED_ATTACHMENT_KINDS.find((kind) => kind.matches(signature))
      : undefined;
    if (
      !detectedKind || detectedKind.mimeType !== claimedMimeType ||
      !detectedKind.extensions.includes(fileExtension(filename))
    ) {
      return {
        attachments: [],
        error: {
          code: "unsupported_attachment_type",
          message:
            "Yalnızca doğrulanmış JPEG, PNG veya PDF dosyaları eklenebilir.",
        },
      };
    }

    attachments.push({
      filename,
      mime_type: detectedKind.mimeType,
      data,
      size_bytes: decodedBytes,
    });
  }

  return { attachments };
}
