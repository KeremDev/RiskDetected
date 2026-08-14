import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { normalizeSupportAttachments } from "./support-attachment-validation.ts";

function encode(bytes: number[]): string {
  return btoa(String.fromCharCode(...bytes));
}

Deno.test("support attachments accept matching JPEG, PNG, and PDF signatures", () => {
  const samples = [
    {
      filename: "ekran.jpg",
      mime_type: "image/jpeg",
      data: encode([0xff, 0xd8, 0xff, 0xdb]),
    },
    {
      filename: "ekran.png",
      mime_type: "image/png",
      data: encode([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    },
    {
      filename: "rapor.pdf",
      mime_type: "application/pdf",
      data: encode([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37]),
    },
  ];

  const result = normalizeSupportAttachments(samples);
  assertEquals(result.error, undefined);
  assertEquals(result.attachments.map((item) => item.mime_type), [
    "image/jpeg",
    "image/png",
    "application/pdf",
  ]);
});

Deno.test("support attachments reject active and executable content", () => {
  for (
    const sample of [
      {
        filename: "payload.html",
        mime_type: "text/html",
        data: btoa("<script>alert(1)</script>"),
      },
      {
        filename: "vector.svg",
        mime_type: "image/svg+xml",
        data: btoa("<svg onload='alert(1)'></svg>"),
      },
      {
        filename: "installer.exe",
        mime_type: "application/octet-stream",
        data: encode([0x4d, 0x5a, 0x90, 0x00]),
      },
    ]
  ) {
    const result = normalizeSupportAttachments([sample]);
    assertEquals(result.error?.code, "unsupported_attachment_type");
    assertEquals(result.attachments, []);
  }
});

Deno.test("support attachments reject extension, MIME, and signature mismatches", () => {
  const png = encode([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  for (
    const sample of [
      { filename: "spoofed.pdf", mime_type: "application/pdf", data: png },
      { filename: "spoofed.jpg", mime_type: "image/png", data: png },
      { filename: "missing-extension", mime_type: "image/png", data: png },
    ]
  ) {
    assertEquals(
      normalizeSupportAttachments([sample]).error?.code,
      "unsupported_attachment_type",
    );
  }
});

Deno.test("support attachment filenames cannot preserve path or control characters", () => {
  const result = normalizeSupportAttachments([{
    filename: "../unsafe\r\nname.jpg",
    mime_type: "image/jpeg",
    data: encode([0xff, 0xd8, 0xff, 0xdb]),
  }]);

  assertEquals(result.error, undefined);
  assertEquals(result.attachments[0].filename, ".._unsafe__name.jpg");
});
