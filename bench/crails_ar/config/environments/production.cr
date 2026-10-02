# Loaded when CRails.env == "production"
if CRails.env.production?
  CRails.application.config.host = "0.0.0.0"
end