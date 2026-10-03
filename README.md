# GR Formela

Aplikacja tylko dla gospodarstwa Formela Adam. Kolejna ferma = kopia tych plików
z własną nazwą, ikoną i osobnym projektem Firebase.

## Pliki
- `index.html` – cała aplikacja
- `manifest.json`, `sw.js`, `icon-*.png`, `apple-touch-icon.png`, `favicon-32.png` – instalacja na telefonie/komputerze (PWA)
- `firestore.rules` – reguły dostępu do bazy
- `infodex_diagnostyka.sql` – zapytanie na komputer klienta (następna wizyta)

## Szybki test bez Firebase
Otwórz `index.html` w przeglądarce (dwuklik). Aplikacja działa w **trybie lokalnym**:
dane zapisują się tylko w tej przeglądarce. Wgraj plik z SOL
w zakładce *Próbne doje*, potem przydziel krowy w zakładce *Grupy*.

## Uruchomienie na Firebase (dostęp z telefonu i komputera)
1. W konsoli Firebase utwórz **nowy projekt** dla tej fermy (np. `gr-formela`).
2. *Firestore Database* → Utwórz bazę (region europe-central2 lub europe-west).
3. *Authentication* → Metoda logowania → włącz **Google**.
4. *Ustawienia projektu* → Twoje aplikacje → dodaj aplikację Web → skopiuj `firebaseConfig`
   i wklej go na górze skryptu w `index.html` (w miejsce `WKLEJ...`).
5. W `firestore.rules` wpisz swój adres e-mail Google, wklej reguły w
   *Firestore → Reguły* i opublikuj.
6. Wgraj pliki na Firebase Hosting tak samo jak Stuchowo
   (`firebase init hosting`, potem `firebase deploy`).
7. Jeśli testowałeś w trybie lokalnym: *Ustawienia → Pobierz kopię (JSON)* przed
   podmianą konfiguracji, a po zalogowaniu *Wczytaj kopię*.

Po każdej zmianie `index.html` podbij `CACHE_NAME` w `sw.js` (grformela-v1 → grformela-v2),
żeby telefony pobrały nową wersję.

## Co jest w aplikacji
- **Grupy**: tablica Nieprzypisane / Grupa 1 / Grupa 2 / Zasuszone. Na komputerze
  przeciąganie myszą, na telefonie dotknięcie krowy i przycisk grupy. Tryb
  zaznaczania wielu krów. Podpowiedzi według dnia laktacji, wpisu „zasuszenie”
  z próbnego doju, planowanej daty wycielenia i nowego wycielenia. Przypinanie,
  historia przesunięć, wydruk listy grup.
- **Stado**: tabela z sortowaniem, filtrami i eksportem do Excela; karta krowy.
- **Próbne doje**: import pliku z SOL z podglądem przed zapisem, historia
  miesięcy, analiza według grup (tabela średnich, listy krów do sprawdzenia:
  T/B, LKS, mocznik, Sket; wykresy mocznik–białko i kg–dzień laktacji, trend).
- **Ustawienia**: progi grup i normy analizy, kopia JSON.

## Następne kroki
1. Wynik `infodex_diagnostyka.sql` z komputera klienta.
2. Agent synchronizujący Infodex → Firebase (numer respondera, zdarzenia, dzienne mleko).
3. Widoki danych z Infodexa w karcie krowy i na wykresach.
