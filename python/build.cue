package python

import (
	"path"
	"dagger.io/dagger"
	"dagger.io/dagger/core"
	"universe.dagger.io/docker"
	"universe.dagger.io/bash"
)

#Image: {
	baseImageTag:	*"public.ecr.aws/docker/library/python:3.10-slim-bullseye" | string
	output:			_build.output
	python:			_version.contents
	os:				_os.contents
	arch:			_arch.contents

	_build: docker.#Build & {
		steps: [
			docker.#Pull & {
				source: baseImageTag
			},
			docker.#Run & {
				command: {
					name: "pip",
					args: ["install", "--upgrade", "pip"]
				}
			}
		]
	}

	_getVersion: bash.#Run & {
		input: _build.output

		script: contents: """
			echo -n `python --version` | sed -e 's/[a-zA-Z0-9.]* *//' > /tmp/python-version
			echo -n `uname -s` > /tmp/os
			echo -n `uname -m` > /tmp/arch
		"""
	}
	_version: core.#ReadFile & {
		input:	_getVersion.output.rootfs
		path:	"/tmp/python-version"
	}
	_os: core.#ReadFile & {
		input:	_getVersion.output.rootfs
		path:	"/tmp/os"
	}
	_arch: core.#ReadFile & {
		input:	_getVersion.output.rootfs
		path:	"/tmp/arch"
	}
}

#AppConfig: {
	path:        string
	buildPath:   string

	venvDir:     "\(path)/venv"
	depsDir:     "\(buildPath)/deps"
	distDir:     "\(buildPath)/dist"
	srcDir:      "\(path)/src"
	
	_reqFile:    "\(buildPath)/requirements.txt"
}

#Run: {
	app:        #AppConfig
	source:     docker.#Image
	workdir:    *"\(app.path)" | string
	mounts:     [name=string]: core.#Mount

	output:     _run.output

	command?: {
		name: *"\(app.venvDir)/bin/python" | string
		args: [...string]
		flags: [string]: (string | true)
	}

	_run: docker.#Run & {
		input:     source
		"workdir": workdir
		"command": command
		"mounts":  mounts
	}
}

#MakeWheel: {
	app:     #AppConfig
	source:  docker.#Image
    project: dagger.#FS

	_build: docker.#Build & {
		steps: [
			docker.#Run & {
				input: source
			}
		]
	}
}

#CreateVirtualenv: {
	app: #AppConfig
	source: docker.#Image

	output: 	_build.output
	location:	app.venvDir

	_build: docker.#Build & {
		steps: [
			bash.#Run & {
				input: source
				script: contents: """
					set -e
					python -m venv --copies \(app.venvDir)
					\(app.venvDir)/bin/pip install --upgrade pip
					\(app.venvDir)/bin/pip install --upgrade wheel
				"""
			}
		]
	}

}

#ExportArtifacts: {
	app:     #AppConfig
	source:  docker.#Image

	_appExport: {
		contents: dagger.#FS & _subdir.output
		_subdir: core.#Subdir & {
			input: source.rootfs
			"path": app.path
		}
	}

	_buildExport: {
		contents: dagger.#FS & _subdir.output
		_subdir: core.#Subdir & {
			input: source.rootfs
			"path": app.buildPath
		}
	}

	export: {
		build: _buildExport.contents
		app:   _appExport.contents
	}
}

// #InstallRequirements: {
// 	virtualenv: #Virtualenv
// 	source:     dagger.#FS
	
// 	_reqFile: "\(virtualenv.path)/requirements.txt"
	
// 	_build: docker.#Build & {
// 		steps: [
// 			docker.#Copy & {
// 				source: source
// 				dest:   _reqFile
// 			},
// 			docker.#Run & {
// 				input: virtualenv.output
// 				command: {
// 					name: "\(virtualenv.path)/bin/pip",
// 					args: ["-r", _reqFile]
// 				}
// 			}
// 		]
// 	}

// 	output: _build.output
// }

#FileRef: {
	input:	dagger.#FS
	source:	string
	
	_targetName: core.#ReadFile & {
		"input":		input
		"path":			source
	}

	targetPath: 		_targetName.contents

	target: core.#ReadFile & {
		"input":		input
		"path":			targetPath
	}
}

#ListGlobSingle: {
	glob:		string
	input: 		docker.#Image

	_loc: "/tmp/tmp-listglobsingle"

	_run: bash.#Run & {
		"input": input
		script: contents: """
			set -e
			cd /
			echo -n `ls \(glob)` > \(_loc)
		"""
	}

	ref: #FileRef & {
		"input":		_run.output.rootfs
		"source":		_loc
	}
}

#InstallWheelFile: {
	app:     #AppConfig
	source:  docker.#Image
	wheel:   string

	output: _run.output

	_run: docker.#Run & {
		input: source
		command: {
			name: "\(app.venvDir)/bin/pip"
			args: ["install", "--no-index", wheel]
		}
	}

	_artifacts: #ExportArtifacts & {
		"app": app
		"source": _run.output
	}

	export: {
		build: _artifacts.export.build
		app:   _artifacts.export.app
	}
}


#PublishPythonPackages: {
	input: docker.#Image

}