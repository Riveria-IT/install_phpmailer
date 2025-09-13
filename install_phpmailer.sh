#!/usr/bin/env bash
# Minimal: PHPMailer per Composer projektlokal installieren
# Optional: Apache2 + Let's Encrypt SSL
# Keine App-/vHost-/ENV-Konfig, nur Pakete & PHPMailer im Zielordner.
# Für Ubuntu/Debian. Mit sudo/root ausführen.

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Bitte mit sudo/root ausführen."; exit 1; }

prompt() {
  local Q="$1" DEF="${2-}" R=""
  if [[ -n "$DEF" ]]; then read -rp "$Q [$DEF]: " R || true; echo "${R:-$DEF}";
  else read -rp "$Q: " R || true; echo "$R"; fi
}

echo "=== PHPMailer Installer (Composer, lokal) ==="

# 1) Zielordner (Standard: /var/www/kontaktmailer -> liegt VOR dem üblichen /var/www/html)
TARGET_DIR="$(prompt 'Zielordner für PHPMailer' '/var/www/kontaktmailer')"
[[ -n "$TARGET_DIR" ]] || { echo "Zielordner ist erforderlich."; exit 1; }

# 2) Optional Apache2 installieren?
INSTALL_APACHE="$(prompt 'Apache2 installieren? (y/N)' 'Y')"

# 3) Optional SSL via Let’s Encrypt einrichten?
USE_SSL='N'
DOMAIN=''
EMAIL_LE=''
if [[ "$INSTALL_APACHE" =~ ^[Yy]$ ]]; then
  USE_SSL="$(prompt 'Let’s Encrypt SSL für eine Domain einrichten? (y/N)' 'N')"
  if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
    DOMAIN="$(prompt 'Domain (z.B. example.com)')"
    [[ -n "$DOMAIN" ]] || { echo "Keine Domain angegeben, SSL wird übersprungen."; USE_SSL='N'; }
    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
      EMAIL_LE="$(prompt 'E-Mail für Let’s Encrypt' "admin@${DOMAIN}")"
    fi
  fi
fi

echo "— Pakete aktualisieren & installieren …"
apt update -y
apt install -y php-cli php-mbstring php-xml php-zip php-curl unzip curl git ca-certificates

if [[ "$INSTALL_APACHE" =~ ^[Yy]$ ]]; then
  apt install -y apache2 certbot python3-certbot-apache
  # Firewall (falls UFW aktiv): 80/443 öffnen
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 'Apache Full' || true
  fi
fi

# Composer installieren (falls fehlt)
if ! command -v composer >/dev/null 2>&1; then
  echo "— Composer installieren …"
  php -r "copy('https://getcomposer.org/installer','composer-setup.php');"
  php composer-setup.php --install-dir=/usr/local/bin --filename=composer
  php -r "unlink('composer-setup.php');"
else
  echo "— Composer vorhanden: $(composer --version)"
fi

# Zielordner anlegen & PHPMailer installieren (projektlokal)
echo "— PHPMailer in '${TARGET_DIR}' installieren …"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"
if [[ ! -f composer.json ]]; then
  composer init -n >/dev/null
fi
composer require phpmailer/phpmailer:^6.9 --no-interaction

# Rechte (für Webserver lesend)
if id -u www-data >/dev/null 2>&1; then
  chown -R www-data:www-data "$TARGET_DIR"
  find "$TARGET_DIR" -type d -exec chmod 750 {} \; || true
  find "$TARGET_DIR" -type f -exec chmod 640 {} \; || true
fi

# Falls der Zielordner doch im Webroot liegt, Zugriff sperren
case "$TARGET_DIR" in
  *"/public/"*|*"/htdocs/"*|*"/html/"*)
    echo "— Hinweis: Ziel liegt unter einem Webroot. Zugriff per .htaccess sperren."
    echo "Require all denied" > "${TARGET_DIR}/.htaccess" || true
    ;;
esac

# Optional: SSL via Certbot (Apache-Plugin) – minimale Apache-Änderungen für HTTPS
if [[ "$INSTALL_APACHE" =~ ^[Yy]$ && "$USE_SSL" =~ ^[Yy]$ && -n "$DOMAIN" ]]; then
  echo "— SSL einrichten: A-Record muss auf den Server zeigen."
  echo "   Wenn du kein IPv6 hast: KEINE AAAA-Records für ${DOMAIN} setzen."
  certbot --apache --agree-tos -m "$EMAIL_LE" -d "$DOMAIN" -d "www.$DOMAIN"
  echo "✅ SSL fertig. Teste:  curl -I https://${DOMAIN}/"
else
  [[ "$INSTALL_APACHE" =~ ^[Yy]$ ]] && echo "— SSL-Konfiguration übersprungen."
fi

echo
echo "✅ Fertig. PHPMailer ist installiert in: ${TARGET_DIR}"
echo
echo "In deiner mailer.php (im selben Ordner) Autoloader einbinden mit:"
echo "    require __DIR__ . '/vendor/autoload.php';"
echo
echo "Beispiel-Test:"
echo "  php -r \"require '${TARGET_DIR}/vendor/autoload.php'; echo (class_exists('PHPMailer\\\\PHPMailer\\\\PHPMailer')?'PHPMailer OK':'FEHLT').PHP_EOL;\""
echo
echo "Hinweis: Es wurden KEINE App-/vHost-/ENV-Konfigurationen deiner Seite vorgenommen."
