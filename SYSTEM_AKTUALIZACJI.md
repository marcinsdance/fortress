# System Aktualizacji Fortress

## 📁 Utworzone Pliki

### Skrypty Systemowe
- **`scripts/fortress-backup.sh`** - Kompletny backup systemu Fortress
- **`scripts/fortress-update.sh`** - Skrypt aktualizacji zachowujący konfiguracje
- **`scripts/fortress-verify.sh`** - Weryfikacja systemu po aktualizacji

### Komendy Fortress
- **`commands/update.cmd`** - Komenda `fortress update`
- **`commands/update.help`** - Pomoc dla komendy update

### Dokumentacja
- **`AKTUALIZACJA.md`** - Szczegółowa instrukcja aktualizacji
- **`SYSTEM_AKTUALIZACJI.md`** - Ten plik - podsumowanie systemu

## 🚀 Instalacja Systemu Aktualizacji

### 1. Skopiuj pliki na serwer VPS

```bash
# Zaloguj się na serwer
ssh root@TWOJ_VPS_IP

# Skopiuj pliki (opcja A: przez git)
cd /tmp
git clone https://github.com/marcinsdance/fortress.git
cp -r fortress/scripts /opt/fortress/
cp fortress/commands/update.* /opt/fortress/commands/
cp fortress/AKTUALIZACJA.md /opt/fortress/
chmod +x /opt/fortress/scripts/*.sh
chmod +x /opt/fortress/commands/update.cmd

# Skopiuj pliki (opcja B: przez scp)
scp scripts/* root@TWOJ_VPS_IP:/opt/fortress/scripts/
scp commands/update.* root@TWOJ_VPS_IP:/opt/fortress/commands/
scp AKTUALIZACJA.md root@TWOJ_VPS_IP:/opt/fortress/
```

### 2. Aktualizuj główny plik fortress

```bash
# Zmodyfikuj /opt/fortress/bin/fortress aby dodać komendę update do pomocy
# Lub zastąp plik nową wersją z tego repozytorium
```

## 📋 Dostępne Komendy

### Komenda `fortress update`

```bash
# Standardowa aktualizacja
fortress update

# Symulacja aktualizacji
fortress update --dry-run

# Aktualizacja z określonej gałęzi
fortress update --branch develop

# Wymuszona aktualizacja
fortress update --force

# Aktualizacja bez backup (niezalecane)
fortress update --no-backup
```

### Dodatkowe funkcje

```bash
# Weryfikacja systemu
fortress update verify

# Backup systemu
fortress update backup

# Informacje o wersji
fortress update version
```

## 🛠️ Funkcje Systemu

### Backup Automatyczny
- Backup wszystkich konfiguracji
- Backup aplikacji i ich danych
- Backup baz danych (PostgreSQL, Redis)
- Backup certyfikatów SSL
- Archiwizacja z automatycznym czyszczeniem

### Aktualizacja Bezpieczna
- Zero downtime dla aplikacji
- Zachowanie wszystkich danych i konfiguracji
- Sprawdzenie kompatybilności przed aktualizacją
- Rollback w przypadku problemów
- Automatyczna weryfikacja po aktualizacji

### Weryfikacja Kompleksowa
- Sprawdzenie wersji systemu
- Weryfikacja struktur katalogów
- Test kontenerów Docker
- Sprawdzenie aplikacji użytkowników
- Test konfiguracji Traefik
- Weryfikacja certyfikatów SSL
- Sprawdzenie zasobów systemowych

## 🔧 Konfiguracja

### Ustawienia Backup
```bash
# Lokalizacja backup'ów
BACKUP_DIR="/opt/fortress/backups/system"

# Liczba zachowywanych backup'ów (domyślnie: 5)
# Modyfikuj w skrypcie fortress-backup.sh
```

### Ustawienia Aktualizacji
```bash
# Domyślna gałąź aktualizacji
UPDATE_BRANCH="main"

# URL repozytorium
REPO_URL="https://github.com/marcinsdance/fortress.git"
```

## 🚨 Rozwiązywanie Problemów

### Problemy z Backup
```bash
# Sprawdź uprawnienia
ls -la /opt/fortress/backups/

# Sprawdź miejsce na dysku
df -h /opt/fortress/

# Sprawdź logi
journalctl -f
```

### Problemy z Aktualizacją
```bash
# Sprawdź połączenie z GitHub
curl -I https://github.com/marcinsdance/fortress.git

# Sprawdź uprawnienia
ls -la /opt/fortress/bin/

# Rollback do poprzedniej wersji
# Użyj instrukcji z AKTUALIZACJA.md
```

### Problemy z Weryfikacją
```bash
# Uruchom weryfikację z szczegółowymi logami
/opt/fortress/scripts/fortress-verify.sh

# Sprawdź raport weryfikacji
cat /tmp/fortress-verification-*.txt
```

## 📊 Monitoring

### Logi Systemowe
```bash
# Logi Docker
journalctl -u docker -f

# Logi Traefik
docker logs fortress_traefik -f

# Logi aplikacji
fortress logs NAZWA_APLIKACJI -f
```

### Metryki Zasobów
```bash
# Użycie zasobów
fortress resources show

# Status systemu
fortress health check --all

# Weryfikacja po aktualizacji
fortress update verify
```

## 🔄 Harmonogram Aktualizacji

### Zalecenia
- **Miesięczne**: Sprawdzenie dostępnych aktualizacji
- **Przed aktualizacją**: Pełny backup systemu
- **Po aktualizacji**: Weryfikacja wszystkich funkcji
- **Monitorowanie**: 24h po aktualizacji

### Automatyzacja (Opcjonalnie)
```bash
# Dodaj do crontab dla regularnych backup'ów
0 2 * * 0 /opt/fortress/scripts/fortress-backup.sh

# Sprawdzenie aktualizacji (bez wykonywania)
0 9 * * 1 /opt/fortress/scripts/fortress-update.sh --dry-run
```

## 📚 Dokumentacja

- **AKTUALIZACJA.md** - Szczegółowa instrukcja krok po kroku
- **Komendy fortress update** - Wbudowana pomoc: `fortress update --help`
- **Logi weryfikacji** - Automatyczne raporty w `/tmp/fortress-verification-*.txt`

---

**Autor**: System Aktualizacji Fortress  
**Wersja**: 1.0  
**Data**: $(date +%Y-%m-%d)  
**Kompatybilność**: Fortress 1.0+