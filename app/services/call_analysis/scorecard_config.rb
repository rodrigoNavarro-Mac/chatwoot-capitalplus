# Carga config/call_scorecards.yml — pesos y umbrales del scorecard por rol (setter/asesor). Ver
# el comentario de cabecera de ese archivo para por qué vive en git y no en una tabla todavía.
class CallAnalysis::ScorecardConfig
  CONFIG_PATH = Rails.root.join('config/call_scorecards.yml')
  RAW = YAML.load_file(CONFIG_PATH).freeze

  # Checksum corto y estable del archivo — se guarda en call_analyses.scorecard_config_version
  # para que cambiar los pesos no altere silenciosamente la lectura de análisis ya guardados.
  VERSION = Digest::SHA256.hexdigest(CONFIG_PATH.read)[0, 12].freeze

  def self.weights(role)
    RAW.dig(role.to_s, 'weights')&.symbolize_keys || {}
  end

  def self.thresholds(role)
    RAW.dig(role.to_s, 'thresholds')&.symbolize_keys || {}
  end

  def self.stage_keys(role)
    weights(role).keys
  end
end
