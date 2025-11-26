fx_version "cerulean"
games {"rdr3"}
rdr3_warning "I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships."
lua54 "yes"

author 'ByteForge, _G[S]cripts'
description 'Gizmo for RedM - Based on gs_gizmo'
version '1.0.7'

shared_script 'config.lua'

client_scripts {
  'utils/*.lua',
  'client/*.lua'
}

ui_page 'web/dist/index.html'

files {
  'locales/*.json',
	'web/dist/index.html',
	'web/dist/**/*',
}

-- Provide 'gs_gizmo' exports
provide 'gs_gizmo'
-- Provide 'object_gizmo' exports
provide 'object_gizmo'