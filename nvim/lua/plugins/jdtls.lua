return {
  'mfussenegger/nvim-jdtls',
  ft = 'java', -- loaded lazily on the first Java buffer; ftplugin/java.lua drives start_or_attach
  dependencies = { 'saghen/blink.cmp' },
}
