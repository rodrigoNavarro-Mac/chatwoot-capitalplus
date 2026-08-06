if @branding
  json.inbox_id @branding.inbox_id
  json.accent_color @branding.accent_color
  json.accent_color_or_default @branding.accent_color_or_default
  json.logo_url @branding.logo_url
  json.letterhead_template_filename @branding.letterhead_template_filename
  json.letterhead_template_attached @branding.letterhead_template.attached?
else
  json.inbox_id @inbox.id
  json.accent_color nil
  json.accent_color_or_default Reports::InboxBranding::DEFAULT_ACCENT_COLOR
  json.logo_url ''
  json.letterhead_template_filename ''
  json.letterhead_template_attached false
end
