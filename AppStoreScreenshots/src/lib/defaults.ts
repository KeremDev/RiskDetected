import { DEFAULT_LOCALE } from "./locale";
import type { Device, ProjectState, Slide } from "./types";

let _id = 0;
export const nid = () => `s_${Date.now().toString(36)}_${(_id++).toString(36)}`;

const tr = (s: string) => ({ [DEFAULT_LOCALE]: s });

function iphoneStarter(): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: tr("RISKDETECTED"),
      headline: tr("Fotoğraftan\nİSG risk analizi"),
      screenshot: "/screenshots/apple/iphone/{locale}/04.png",
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: tr("FOTOĞRAF"),
      headline: tr("Sahadan çek,\nanında tara"),
      screenshot: "/screenshots/apple/iphone/{locale}/01.png",
      inverted: true,
    },
    {
      id: nid(),
      layout: "two-devices",
      label: tr("ODAKLI ANALİZ"),
      headline: tr("Tehlikeli alanı\nkendin işaretle"),
      screenshot: "/screenshots/apple/iphone/{locale}/05.png",
      screenshotSecondary: "/screenshots/apple/iphone/{locale}/02.png",
    },
    {
      id: nid(),
      layout: "device-top",
      label: tr("AI ÖZETİ"),
      headline: tr("Riskleri\nderinlemesine gör"),
      screenshot: "/screenshots/apple/iphone/{locale}/08.png",
      inverted: true,
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: tr("METOTLAR"),
      headline: tr("Fine-Kinney\nve 5x5 hazır"),
      screenshot: "/screenshots/apple/iphone/{locale}/06.png",
    },
    {
      id: nid(),
      layout: "device-top",
      label: tr("RAPOR"),
      headline: tr("PDF veya Excel\nraporu oluştur"),
      screenshot: "/screenshots/apple/iphone/{locale}/03.png",
      inverted: true,
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: tr("ÇIKTI"),
      headline: tr("Risk tablon\ntek dokunuşta"),
      screenshot: "/screenshots/apple/iphone/{locale}/09.png",
    },
    {
      id: nid(),
      layout: "two-devices",
      label: tr("BAŞLANGIÇ"),
      headline: tr("Kamera ya da\ngaleriden başla"),
      screenshot: "/screenshots/apple/iphone/{locale}/07.png",
      screenshotSecondary: "/screenshots/apple/iphone/{locale}/01.png",
      inverted: true,
    },
    {
      id: nid(),
      layout: "no-device",
      label: tr("SAHA İÇİN HIZLI KARAR"),
      headline: tr("Fotoğraf\nAnaliz\nRapor"),
      screenshot: "",
    },
  ];
}

function makeStarterSlides(): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: tr("RISKDETECTED"),
      headline: tr("Fotoğraftan\nriskleri yakala"),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: tr("ÖZELLİK"),
      headline: tr("Hızlı analiz\nhazır rapor."),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "two-devices",
      label: tr("RAPOR"),
      headline: tr("PDF ve Excel\nçıktısı al."),
      screenshot: "",
      screenshotSecondary: "",
    },
    {
      id: nid(),
      layout: "device-top",
      label: tr("METOT"),
      headline: tr("Fine-Kinney\nve 5x5."),
      screenshot: "",
      inverted: true,
    },
    {
      id: nid(),
      layout: "no-device",
      label: tr("ÖZET"),
      headline: tr("Fotoğraf\nAnaliz\nRapor."),
      screenshot: "",
    },
  ];
}

function ipadStarter(): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: tr("RISKDETECTED"),
      headline: tr("Büyük ekranda\nrisk analizi."),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: tr("ODAK"),
      headline: tr("Saha bulgularını\ndüzenle."),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "device-top",
      label: tr("RAPOR"),
      headline: tr("Raporu hazırla."),
      screenshot: "",
      inverted: true,
    },
  ];
}

function tabletStarter(kind: "7" | "10"): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: tr("RISKDETECTED"),
      headline: tr(kind === "7" ? "Sahada\nhızlı karar." : "Ekipler için\nrisk görünümü."),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "split-landscape",
      label: tr("RAPOR"),
      headline: tr("Geniş tabloda\nnet sonuç."),
      screenshot: "",
    },
  ];
}

function fgStarter(): Slide[] {
  return [
    {
      id: nid(),
      layout: "feature-graphic",
      label: {},
      headline: tr("Fotoğraftan İSG risk analizi ve rapor."),
      screenshot: "",
    },
  ];
}

export const DEFAULT_PROJECT: ProjectState = {
  appName: "RiskDetected",
  themeId: "dark-bold",
  locales: [DEFAULT_LOCALE],
  locale: DEFAULT_LOCALE,
  device: "iphone",
  orientation: "portrait",
  appIcon: "/app-icon.png",
  slidesByDevice: {
    iphone: iphoneStarter(),
    android: makeStarterSlides(),
    ipad: ipadStarter(),
    "android-7": tabletStarter("7"),
    "android-10": tabletStarter("10"),
    "feature-graphic": fgStarter(),
  },
};

export function newSlide(layout: Slide["layout"] = "device-bottom"): Slide {
  return {
    id: nid(),
    layout,
    label: tr("YENİ"),
    headline: tr("Başlığı\nburaya yaz."),
    screenshot: "",
  };
}

export function detectPlatform(device: Device): "ios" | "android" {
  return device === "iphone" || device === "ipad" ? "ios" : "android";
}
