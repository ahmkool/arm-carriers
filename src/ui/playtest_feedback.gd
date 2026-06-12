class_name PlaytestFeedback

const DISCORD_URL := "https://discord.gg/CvPmvmzFPZ"
const HOME_MENU_NOTICE := "This is a playtest build. I'd love your feedback and ideas for improvements!"
const LEVEL_COMPLETE_NOTICE := "Level complete — congratulations!\n\nThis is a playtest build. Share your feedback on Discord!"
const DISCORD_BUTTON_TEXT := "Join Discord"


static func open_discord() -> void:
	OS.shell_open(DISCORD_URL)
