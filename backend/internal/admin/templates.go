package admin

import (
	"embed"
	"html/template"
)

//go:embed templates/*.html
var templatesFS embed.FS

func LoadTemplates() (*template.Template, error) {
	return template.ParseFS(templatesFS, "templates/*.html")
}
