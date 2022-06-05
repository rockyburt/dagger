#InstallSystemPoetry: {
	input:		docker.#Image
	output:		_run.output
	
	_run: docker.#Run & {
		"input": input
		command: {
			name: "/usr/local/bin/pip"
			args: ["install", "poetry"]
		}
	}
}

#InstallPoetryRequirements: {
	app:      #AppConfig
	source:   docker.#Image
	project:  dagger.#FS
	name:     string

	_reqFile: "\(app.buildPath)/requirements.txt"

	_copyFiles: #CopyPoetryFiles & {
		input:		source
		"project": 	project
	}

	_run: docker.#Build & {
		steps: [
			#InstallSystemPoetry & {
				input: _copyFiles.output
			},
			bash.#Run & {
				workdir: _copyFiles.dest
				script: contents: """
					set -e
					mkdir -p \(app.buildPath)
					/usr/local/bin/poetry export --format requirements.txt --dev --without-hashes > \(_reqFile)
				"""
			},
			bash.#Run & {
				script: contents: """
					set -e
					mkdir -p \(app.depsDir)
					\(app.venvDir)/bin/pip wheel -w \(app.depsDir) -r \(_reqFile)
					\(app.venvDir)/bin/pip install --no-index -f \(app.depsDir) -r \(_reqFile)
				"""
			},
		]
	}

	_artifacts: #ExportArtifacts & {
		"app": app
		"source": _run.output
	}

	export: {
		build: _artifacts.export.build
		app:   _artifacts.export.app
	}

	output: _run.output
}


#BuildPoetrySourcePackage: {
	app:		#AppConfig
	source:		docker.#Image
	project:	dagger.#FS
	
	output:		_run.output

	name:		_version.packageName
	version:	_version.packageVersion

	bdistWheelFile:	path.Base(bdistWheel.ref.targetPath)
	sdistFile:		path.Base(sdist.ref.targetPath)

	_version: #GetPackageVersionByPoetry & {
		"source":	source
		"project":	project
	}

	bdistWheel: #ListGlobSingle & {
		glob: "\(app.distDir)/\(name)/*.whl"
		input: _run.output
	}
	sdist: #ListGlobSingle & {
		glob: "\(app.distDir)/\(name)/*.tar.gz"
		input: _run.output
	}

	_run: bash.#Run & {
		input: source
		mounts: projectMount: {
			dest:     workdir
			contents: project
		}
		workdir: "\(app.srcDir)/\(name)"
		script: contents: """
			set -e
			rm -Rf dist
			poetry build
			mkdir -p \(app.distDir)/\(name)
			cp dist/* \(app.distDir)/\(name)/
		"""
	}

	_artifacts: #ExportArtifacts & {
		"app": app
		"source": _run.output
	}
	export: {
		build: _artifacts.export.build
		app:   _artifacts.export.app
		dist: {
			"bdistWheel": bdistWheel.ref.target
			"sdist":      sdist.ref.target
		}
	}
}

#CopyPoetryFiles: {
	input: 		docker.#Image
	project: 	dagger.#FS
	dest:		"/package"
	output:		_run.output
	
	_run: docker.#Copy & {
		"input": input
		contents: project
		include: ["poetry.lock", "pyproject.toml"]
		"dest": dest
	}

}

#GetPackageVersionByPoetry: {
	source:		docker.#Image
	project:	dagger.#FS

	packageName: 	_outputName.contents
	packageVersion:	_outputVersion.contents

	_outputName: core.#ReadFile & {
		"input":		_run.output.rootfs
		"path":			"/tmp/PACKAGE_NAME"
	}
	_outputVersion: core.#ReadFile & {
		"input":		_run.output.rootfs
		"path":			"/tmp/PACKAGE_VERSION"
	}

	_install_poetry: #InstallSystemPoetry & {
		input: source
	}

	_copyFiles: #CopyPoetryFiles & {
		input: _install_poetry.output
		"project": project
	}

	_run: bash.#Run & {
		input: _copyFiles.output
		workdir: _copyFiles.dest
		script: contents: """
			echo -n `poetry version` > /tmp/full-version
			cat /tmp/full-version | sed -e 's/\\([a-zA-Z0-9_-]\\+\\)\\(.*\\)/\\1/' > /tmp/PACKAGE_NAME
			cat /tmp/full-version | sed -e 's/\\([a-zA-Z0-9_-]\\+\\) *\\(.*\\)/\\2/' > /tmp/PACKAGE_VERSION
		"""
	}
}
