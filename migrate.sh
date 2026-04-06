#!/bin/bash

# Detect package manager
if command -v apt &> /dev/null; then
    PM="apt"
    UPDATE="sudo apt update"
    INSTALL="sudo apt install -y"
elif command -v dnf &> /dev/null; then
    PM="dnf"
    UPDATE="sudo dnf check-update || true"
    INSTALL="sudo dnf install -y"
elif command -v yum &> /dev/null; then
    PM="yum"
    UPDATE="sudo yum check-update || true"
    INSTALL="sudo yum install -y"
else
    echo "No supported package manager found (apt, dnf, yum)"
    exit 1
fi

php81="/usr/local/lsws/lsphp81/bin/php"
verbose=""

for arg in "$@"; do
    if [[ "$arg" == "-v" ]]; then
        verbose="-v"
    fi
done

if [ ! -x "$php81" ]; then
    echo "PHP 8.1 is not installed at $php81."
    echo "Please install PHP 8.1 or ensure it is available at the specified path."
    exit 1
fi

# Check if config.ini exists
if [ ! -f "config.ini" ]; then
    echo "Error: config.ini not found."
    echo "Please copy config.ini.template to config.ini and fill in the remote server information."
    echo "Then run the script again."
    exit 1
fi

# Read remote password from config.ini
remotePassword=$(grep '^password' config.ini | cut -d'=' -f2 | tr -d ' '| tr -d '"' )

if [ -n "$remotePassword" ] && ! type -P sshpass &>/dev/null; then
    echo "sshpass is not installed. Installing it now..."

    # Update package list and install sshpass
    $UPDATE
    install_log=$($INSTALL sshpass 2>&1)

    if ! type -P sshpass &>/dev/null; then
        echo "Installation of sshpass failed. See the log below:"
        echo "$install_log"
        exit 1
    else
        echo "sshpass has been successfully installed."
    fi
fi

$php81 migrate-scripts/00-migrate-info.php

echo "if You are sure about that, type 'yes' and press enter: "
read -r answer
if [ "$answer" != "yes" ]; then
    echo "Aborting..."
    exit 1
fi

echo "Running migrations..."
echo -e "\n**********Migrating websites**********"
$php81 migrate-scripts/01-migrate-websites.php "$@"
if [ $? -ne 0 ]; then
    echo "Error during website migration. Exiting."
    exit 1
fi

echo -e "\n**********Migrating emails**********"
$php81 migrate-scripts/02-migrate-emails.php "$@"
if [ $? -ne 0 ]; then
    echo "Error during email migration. Exiting."
    exit 1
fi

echo -e "\n**********Migrating databases**********"
$php81 migrate-scripts/03-migrate-websites-databases.php "$@"
if [ $? -ne 0 ]; then
    echo "Error during database migration. Exiting."
    exit 1
fi

echo -e "\n**********Migrating data**********"
$php81 migrate-scripts/04-migrate-websites-data.php "$@"
if [ $? -ne 0 ]; then
    echo "Error during data migration. Exiting."
    exit 1
fi

echo -e "\n**********Migrating email data**********"
$php81 migrate-scripts/05-migrate-websites-vmail.php "$@"
if [ $? -ne 0 ]; then
    echo "Error during email data migration. Exiting."
    exit 1
fi

echo -e "\n\nAll migrations completed."
