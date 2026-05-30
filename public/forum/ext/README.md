# Registration Honeypot Extension for phpBB3

A fully ACP-configurable honeypot anti-spam extension. No hardcoded text — all settings controlled via the admin panel.

## How It Works

1. A hidden HTML field is injected into the registration form
2. CSS hides it from human visitors
3. Bots parsing the HTML see the field and its "explanation" text
4. The explanation can bait bots into entering a specific value
5. Any non-empty value = registration silently rejected
6. Real humans never see the field = registration succeeds

## Installation

### Step 1: Upload Extension

Copy the `ext/generic` folder to your phpBB installation's `ext/` directory:

```
your_forum/
└── ext/
    └── generic/
        └── honeypot/
            ├── composer.json
            ├── ext.php
            ├── config/
            ├── event/
            ├── acp/
            ├── migrations/
            ├── language/
            ├── styles/
            └── adm/
```

### Step 2: Enable Extension

1. Go to **ACP > Customise > Manage extensions**
2. Find "Registration Honeypot" and click **Enable**

### Step 3: Configure Settings

1. Go to **ACP > Extensions > Registration Honeypot**
2. Configure your honeypot:
   - **Enable honeypot**: Turn on/off
   - **Field name**: HTML input name (e.g., `website_url`, `company`)
   - **Field label**: What bots see as the field label
   - **Bot bait text**: Explanation text to trick bots (e.g., "The answer is 42")
   - **Error message**: Generic message shown on rejection

## Example Configuration

For an Ohio Scientific forum:

| Setting | Value |
|---------|-------|
| Field name | `osi_board_model` |
| Field label | `Model Number of Superboard II` |
| Bot bait | `Captcha: Humans know the model number is 600. Enter it to verify you are human.` |
| Error message | `Registration could not be completed. Please try again later.` |

Bots see the "600" hint and fill it in. Humans never see the field. Any filled value = rejected.

## Tips

- Use tempting field names: `website`, `url`, `company`, `phone`, `fax`
- Avoid obvious names: `honeypot`, `trap`, `spam`
- Keep error messages generic to not reveal the trap
- The "bot bait" text can explicitly tell bots what to enter — they'll comply!

## Requirements

- phpBB 3.2.0 or higher
- PHP 7.2 or higher

## License

GPL-2.0-only
