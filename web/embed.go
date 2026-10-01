package web

import (
	"embed"
	"io/fs"
)

//go:embed all:dist
var distFS embed.FS

// DistFS returns an fs.FS sub-rooted at "dist", allowing direct access to static files like index.html.
func DistFS() (fs.FS, error) {
	return fs.Sub(distFS, "dist")
}
