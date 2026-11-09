# 📝 MeetNotes

[![License: Atıf Zorunlu | Ticari Yasak](https://img.shields.io/badge/Lisans-Atıf%20Zorunlu%20%7C%20Ticari%20Yasak-red.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%20%7C%20Cross--Platform-black?logo=apple)](https://flutter.dev)

> **MeetNotes**, modern, akıcı ve güçlü bir dijital not alma, çizim ve haftalık/günlük ajanda uygulamasıdır. Apple Notes sadeliğini profesyonel vektörel çizim araçları, birleşik katmanlama sistemi, PDF sayfa aktarımı ve akıllı sayfa düzenleriyle bir araya getirir.

---

## 🌟 Öne Çıkan Özellikler

### ✍️ 1. Gelişmiş Çizim ve Kalem Araçları
- **Apple Notes Tarzı Kenetlenebilir Araç Çubuğu:** Ekranın alt, üst, sol ve sağ kenarlarına dinamik olarak kenetlenen, yatay/dikey form alabilen modern kayan araç çubuğu (`AppleNotesFloatingToolbar`).
- **Geniş Kalem Yelpazesi:**
  - Tükenmez Kalem, Dolma Kalem, Monoline Kalem, Kurşun Kalem
  - Fosforlu Kalem (Marker), Sulu Boya (Watercolor), Pastel Boya (Crayon)
  - Akıllı Vektör & Piksel Silgi (Eraser)
- **Akıllı Çizgi & Şekil Kütüphanesi:**
  - Düz Çizgi, Ok Çizgisi, 3 Noktalı Kavisli Çizgi (Bezier tutamaçları ile bükülebilir)
  - 3 Noktalı Dinamik Açı
  - Dikdörtgen, Kare, Daire, Elips, Üçgen, Beşgen, Altıgen ve Deltoid
  - Tüm şekiller için hem çerçeveli (outlined) hem de içi dolu (filled) varyantlar
- **Manyetik Uç Yakalama (Magnetic Snapping):** Çizgilerin, okların ve şekillerin uç ve köşe noktaları birbirine yaklaştığında mıknatıs gibi kenetlenir.

---

### 🔲 2. Kement & Seçim Sistemi (Lasso & Transform)
- **Anchored Seçim Diyaloğu (`CompactLassoPickerDialog`):** Kement butonuna dokunulduğunda açılan cam efekti popover.
- **Çoklu Seçim Modu:**
  - **Kare / Dikdörtgen Seçim:** Çapraz sürükleme ile kare veya dikdörtgen bir alan çizerek içindeki tüm öğeleri anında seçer.
  - **Serbest Kement:** El serbestisiyle çizilen kapalı eğri içerisindeki öğeleri seçer.
- **Birleşik Dönüştürme Kutusu:**
  - 8 yönlü yeniden boyutlandırma tutamaçları
  - 2D serbest döndürme sapı (rotation stem)
  - Çizimleri, metinleri ve görselleri tek seferde birlikte taşıma, döndürme ve ölçeklendirme
  - Kopyalama (Duplicate), Silme (Delete) ve Kilitleme (Lock) desteği

---

### 📑 3. Birleşik Katmanlama Sistemi (Unified Layer Architecture)
- **Gerçek Zamanlı Z-Order:** Çizim darbeleri, metin kutuları, yapışkan notlar ve tuval görselleri tek bir katman sıralamasında yönetilir.
- **Hızlı Erişim Katmanlar Paneli:**
  - Katmanları sürükle-bırak ile öne veya arkaya taşıma
  - Her katman için canlı küçük resim önizlemesi ve kilit kontrolü
  - Yalnızca seçili katmanları filtreleme imkanı

---

### 📄 4. Dosyalar & PDF Entegrasyonu
- **PDF Belge Yönetimi:** Cihazdan PDF dosyalarını içe aktarma ve dosya listesinde güvenle saklama.
- **Yerel PDF Sayfa Görüntüleyici:** PDF sayfalarını yüksek çözünürlüklü küçük resimler halinde inceleme.
- **Tuvale Sürükle-Bırak:** PDF içindeki herhangi bir sayfayı basılı tutup doğrudan çalışma alanına bırakabilme.
- Sayfa en-boy oranını (aspect ratio) otomatik koruyarak bağımsız katman olarak konumlandırma.

---

### 🖼️ 5. Fotoğraf & Görsel Yönetimi
- Cihaz galerisinden veya dosyalardan fotoğraf/resim ekleme.
- Tuval üzerinde kesintisiz yakınlaştırma, döndürme, kilit mekanizması ve 60 FPS performans için bellek önbelleklemesi (memory bytes cache).

---

### 📝 6. Metin Kutuları & Yapışkan Notlar (Sticky Notes)
- Düz metin kutuları ve renkli Post-it tarzı yapışkan notlar.
- **Google Fonts Entegrasyonu:** `CompactFontPickerDialog` ile kategorilendirilmiş modern yazı tipleri.
- Yazı boyutu, kalınlık (bold), eğiklik (italic), altı çizili (underline), metin hizalama ve köşe yuvarlatma kontrolleri.

---

### 🎨 7. Renk & Çizgi Kalınlığı Paletleri
- **Renk Seçici (`CompactColorPickerDialog`):** Renk tekerleği, hassas opaklık/şeffaflık kaydırıcısı ve hazır renk paletleri.
- **Çizgi Ayarları (`CompactStrokeWidthPicker`):** Anlık nokta önizlemesi, artı/eksi adımlayıcılar ve hassas slider kontrolleri.

---

### 📐 8. Sayfa Düzeni & Şablonlar (Hızlı Erişim İçinde)
- **4 Temel Şablon:** Kareli (Grid), Çizgili (Lined), Noktalı (Dotted) ve Boş (Blank).
- **Hassas Çizgi/Kare Boyutu:** `20 pt` - `56 pt` aralığında canlı ayar.
- **Çizgi Belirginliği:** `%8` - `%45` arasında opaklık ayarı.
- **Orta Defter Katlama İzi:** Kitapçık ve ajanda formatında orta kıvrım çizgisi desteği.

---

### 📅 9. Haftalık & Günlük Ajanda
- **Hero Geçiş Animasyonu:** Haftalık genel bakış kartlarına dokunulduğunda akıcı şekilde tam ekran tuvale genişleme.
- **Görevler & Günler Yan Menüleri:** Sayfayı bölmeden görev takibi ve günler arası hızlı geçiş.
- **Yerel Veri Saklama:** Çizimlerin ve notların `SharedPreferences` ve yerel dosya sistemine güvenle kaydedilmesi.

---

## 🛠️ Teknoloji Yığını

- **Framework:** [Flutter](https://flutter.dev/) (Channel stable, macOS & Cross-platform)
- **Dil:** [Dart](https://dart.dev/)
- **Çizim Motoru:** Özel `CustomPainter` mimarisi (GPU ivmeli çift katmanlı çizim, ayrık seçim bindirmesi)
- **Depolama:** `shared_preferences`, `path_provider`, dosya tabanlı JSON serileştirme
- **Tipografi:** `google_fonts`
- **Dosya Seçici:** `file_picker`
- **Tarih & Yerelleştirme:** `intl` (Tam Türkçe `tr_TR` desteği)
- **İkon Seti:** `Material Icons` & `Cupertino Icons`

---

## 🚀 Kurulum ve Çalıştırma

Projeyi yerel makinenizde çalıştırmak için:

1. **Depoyu klonlayın:**
   ```bash
   git clone https://github.com/tekneenes/MeetNotes.git
   cd MeetNotes
   ```

2. **Bağımlılıkları yükleyin:**
   ```bash
   flutter pub get
   ```

3. **Testleri çalıştırın:**
   ```bash
   flutter test test/widget_test.dart
   ```

4. **Uygulamayı başlatın (macOS):**
   ```bash
   flutter run -d macos
   ```

---

## 📁 Proje Dizin Yapısı

```
lib/
├── controllers/          # PlannerController (iş mantığı, seçim, araçlar, katmanlar)
├── models/               # Veri modelleri (Stroke, Layer, Text, Image, File, PaperConfig)
├── painters/             # Çizim motoru (DrawingCanvasPainter)
├── services/             # PdfService, PlannerStorageService
├── views/                # PlannerScreen (Ana ekran, haftalık & günlük tuval, hızlı erişim)
└── widgets/              # AppleNotesToolbar, CompactLassoPicker, ColorPicker vb. bileşenler
```

---

## 📄 Lisans ve Kullanım Koşulları

Bu projenin tüm hakları **Muhammed Enes Tekne**'ye aittir. Proje, aşağıdaki özel lisans ve kullanım koşullarına tabidir:

- 📌 **Atıf Zorunludur (Attribution Required):** Bu projenin kaynak kodları, mimarisi, görsel tasarımı veya türevleri herhangi bir yerde kullanıldığında, orijinal geliştiriciye (**Muhammed Enes Tekne**) ve bu [GitHub Deposuna](https://github.com/tekneenes/MeetNotes) açık, görünür ve tıklanabilir bir şekilde atıf yapılması zorunludur.
- 🚫 **Ticari Kullanım Kesinlikle Yasaktır (Proje Sahibi Hariç):** Proje sahibi (**Muhammed Enes Tekne**) **hariç** hiçbir gerçek veya tüzel kişi, şirket veya organizasyon; bu yazılımı, kaynak kodlarını, bileşenlerini veya türevlerini doğrudan ya da dolaylı olarak **ticari amaçla kullanamaz, satamaz, kiralayamaz, ücretli/abonelikli servislere dahil edemez ve gelir elde etmek amacıyla dağıtamaz**.
- ✅ **Kişisel ve Eğitsel Kullanım:** Proje kaynak kodları yalnızca ticari olmayan kişisel inceleme, eğitim, araştırma ve açık kaynak gelişimine katkı sağlamak amacıyla serbestçe incelenebilir ve kullanılabilir.

Detaylı yasal şartlar ve maddeler için lütfen [LICENSE](LICENSE) dosyasını inceleyiniz.
