declare var modules
import * as fs from 'fs'

class Module {

	private view2dview
	private	viewini3dview
	private cavgsview
	private ini3diterationview
	private ptclsview2d
	private ptclsview
	private pack
	private importmoviesview
	private ctfview
	
	public metadata = {
			"moduletitle" :"Simple",
			"modulename" :"simple",
			"tasks" : {
			}
	}
		
	constructor(){
		process.stdout.write("Loading module - Simple ... ")
		var interfacejson = require("./simple_user_interface.json")
		for(var command of interfacejson){
			var commandkeys = Object.keys(command)
			var task = command[commandkeys[0]]
			task['pages'] = []
			for(var i = 1; i < commandkeys.length; i++){
				var page = {}
				page['title'] = commandkeys[i]
				page['keys'] = []
				for(var key of command[commandkeys[i]]){
					page['keys'].push(key)
				}
				if(page['keys'].length > 0){
					task['pages'].push(page)
				}
			}
			this.metadata['tasks'][commandkeys[0]] = task
		}
		const pug = require('pug')
		this.pack = require("../../../external/DensityServer/build/pack/main.js")
		this.view2dview = pug.compileFile('views/simple-view2d.pug')
		this.viewini3dview = pug.compileFile('views/simple-viewini3d.pug')
		this.cavgsview = pug.compileFile('views/simple-cavgs.pug')
		this.ini3diterationview = pug.compileFile('views/simple-ini3diteration.pug')
		this.ptclsview2d = pug.compileFile('views/simple-viewptcls2d.pug')
		this.ptclsview = pug.compileFile('views/simple-viewptcls.pug')
		this.importmoviesview = pug.compileFile('views/simple-viewimportmics.pug')
		this.ctfview = pug.compileFile('views/simple-viewctf.pug')
		process.stdout.write("Done\n")
	}
	
	public refineSelection(file){
		var spawn = require('child-process-promise').spawn
		var stat = fs.lstatSync(file)
		if(stat.isFile()){
			if(file.includes(".simple")){
				var command = "simple_exec"
				var commandargs = []
				commandargs.push("prg=print_project_info")
				commandargs.push("projfile=" + file)
				return spawn(command, commandargs, {capture: ['stdout']})
					.then((result) => {
						var taskarray = []
						if(result.stdout.includes("per-micrograph stack")){
							taskarray.push("ctf_estimate")
						}else{
							taskarray.push("import_movies")
						}
						if(result.stdout.includes("per-particle 2D")){
							taskarray.push("cluster2D")
						}else{
							taskarray.push("import_particles")
						}
						if(result.stdout.includes("per-particle 3D" )){
							taskarray.push("postprocess")
						}else{
							taskarray.push("")
						}
						return taskarray
					})
			}
		}else if(stat.isDirectory()){
			return new Promise((resolve, reject) => {
				var taskarray = []
				taskarray.push("preprocess_stream")
				resolve(taskarray)
			})
		}
	}
	
	public execute(modules, arg){
		var spawn = require('child_process').spawn
		var command = arg['executable']
		var type = arg['type']
		var inputpath = arg['inputpath']
		var keys = arg['keys']
		var keynames = Object.keys(keys);
		var commandargs = []
		commandargs.push("prg=" + type)
		commandargs.push("projfile=" + inputpath)
		commandargs.push("mkdir=no")
		for(var key of keynames){
			if(keys[key] != ""){
				if(keys[key] == "true"){
					commandargs.push(key.replace('key', '') + "=yes")
				}else if(keys[key] == "false"){
					commandargs.push(key.replace('key', '') + "=no")
				}else{
					commandargs.push(key.replace('key', '') + "=" + keys[key])
				}
			}
		}
		
		
		
		arg['view'] = ""
	
		if(type == "cluster2D") {
		//	arg['view'] = "{ \"mod\" : \"simple\", \"fnc\" : \"view2d\" }"
			arg['view'] = {mod : "simple", fnc : "view2d"}
		}else if(type == "initial_3Dmodel") {
			arg['view'] = "{ \"mod\" : \"simple\", \"fnc\" : \"viewini3d\" }"
		}else if(type == "import_movies") {
			arg['view'] = "{ \"mod\" : \"simple\", \"fnc\" : \"viewImportMovies\" }"
		}else if(type == "ctf_estimate") {
			arg['view'] = "{ \"mod\" : \"simple\", \"fnc\" : \"viewCTFEstimate\" }"
		}else if(type == "import_particles") {
			arg['view'] = "{ \"mod\" : \"simple\", \"fnc\" : \"viewParticles\" }"
		}else if(type == "extract") {
			arg['view'] = "{ \"mod\" : \"simple\", \"fnc\" : \"viewParticles\" }"
		}
		
		console.log(command, commandargs)
		
		return modules['available']['core']['taskCreate'](modules, arg)
			.then((json) => {
				var executeprocess = spawn(command, commandargs, {detached: true, cwd: json['jobfolder']})
				executeprocess.on('exit', function(code){
					console.log(`child process exited with code ${code}`);
					modules['available']['core']['updateStatus'](arg['projecttable'], json['jobid'], "Finished")
				})
				executeprocess.stdout.on('data', (data) => {
					console.log(`child stdout:\n${data}`)
				})
				executeprocess.stderr.on('data', (data) => {
					console.log(`child stderr:\n${data}`)
				})
				executeprocess.on('error', function(error){
					console.log(`child process exited with error ${error}`)
					modules['available']['core']['updateStatus'](arg['projecttable'], json['jobid'], "Error")
				})
				
				console.log(`Spawned child pid: ${executeprocess.pid}`)
				modules['available']['core']['updatePid'](arg['projecttable'], json['jobid'], executeprocess.pid)
				
				return({})
			})
	}
	
	public view2d (modules, arg) {
		var contents = fs.readdirSync(arg['folder'])
		var iterations = []
		for(var file of contents){
			if(file.includes("cavgs") && file.includes(".mrc") && ! file.includes("even") && ! file.includes("odd") && ! file.includes("ranked")){
				iterations.push(file)
			}
		}
		iterations.sort()
		var view = {}
		view['iterations'] = iterations
		view['status'] = arg['status']
		view['folder'] = arg['folder']
		return new Promise((resolve, reject) => {
			resolve({html : this.view2dview(view)})
		})
	}
	
	public getCavgs (mods, arg) {
		var spawn = require('child-process-promise').spawn
		var path = require('path')
		var view = {}
		if(arg['status']) {
			var projfile = path.dirname(arg['file']) + "/project.simple"
			var command = "simple_exec"
			var commandargs = []
			commandargs.push("prg=print_project_field")
			commandargs.push("projfile=" + projfile)
			commandargs.push("oritype=cls2D")
			var cavgarray = []
			return spawn(command, commandargs, {capture: ['stdout']})
				.then((result) => {
					var lines = result.stdout.split("\n")
					for(var line of lines){
						var cavg = {}
						var elements = line.split(" ")
						for(var element of elements){
							var key = element.split("=")[0]
							var value = element.split("=")[1]
							cavg[key] = value
						}
						cavgarray.push(cavg)
					}
					return 
				})
				.then (() => {
					return modules['available']['core']['readMRCHeader'](arg['file'])
				})
				.then((header) => {
					view['thumbcount'] = header['nz'] 
					view['path'] = arg['file']
					view['status'] = arg['status']
					view['cavgarray'] = cavgarray
					view['folder'] = path.dirname(arg['file'])
					view['projectfile'] = projfile
					return({html : this.cavgsview(view)})
				})
		} else {
			return modules['available']['core']['readMRCHeader'](arg['file'])
				.then((header) => {
					view['thumbcount'] = header['nz']
					view['path'] = arg['file']
					view['status'] = arg['status']
					return({html : this.cavgsview(view)})
				})
		}
	}
	
	public viewini3d (modules, arg) {
		var contents = fs.readdirSync(arg['folder'])
		var iterations = []
		for(var file of contents){
			if(file.includes("recvol_state01_iter") && ! file.includes("pproc")){
				iterations.push(file)
			}
		}
		iterations.sort()
		var view = {}
		view['iterations'] = iterations
		
		if(fs.existsSync(arg['folder'] + "/rec_final.mrc")){
			view['final'] = true
		}
		
		view['status'] = arg['status']
		view['folder'] = arg['folder']
		return new Promise((resolve, reject) => {
			resolve({html : this.viewini3dview(view)})
		})
	}
	
	public viewIni3dIteration(modules, arg) {
		var id = Math.floor(Math.random() * 10000)
		var config = {
				input: [ { name: 'em', filename: arg['file']}],
				isPeriodic: false,
				outputFilename: "/tmp/" + id + ".mdb",
				blockSize: 96
			}
		var view = {}
		if(arg['file'].includes("final")){
			view['final'] = true
		}
		return(this.pack.default(config.input, config.blockSize, config.isPeriodic, config.outputFilename))
		.then(() => {
				return({html : this.ini3diterationview(view), mdb : id})
		})
	}
	
	public setupProject(arg){
		var spawn = require('child_process').spawn
		var command = "simple_exec"
		var commandargs = []
		commandargs.push("prg=new_project")
		commandargs.push("projname=project")
		var executeprocess = spawn(command, commandargs, {detached: true, cwd: arg['keys']['keyfolder']})
		executeprocess.on('exit', function(code){
			console.log(`child process exited with code ${code}`)
			fs.renameSync(arg['keys']['keyfolder'] + "/project/project.simple", arg['keys']['keyfolder'] + "/project.simple")
			fs.rmdirSync(arg['keys']['keyfolder'] + "/project")
		})
		executeprocess.stdout.on('data', (data) => {
			console.log(`child stdout:\n${data}`)
		})
		executeprocess.stderr.on('data', (data) => {
			console.log(`child stderr:\n${data}`)
		})
		executeprocess.on('error', function(error){
			console.log(`child process exited with error ${error}`)
		})
		
		console.log(`Spawned child pid: ${executeprocess.pid}`)

	}
	
	public save2DSelection(modules, arg){
		var spawn = require('child-process-promise').spawn
		fs.copyFileSync(arg['projectfile'], arg['file'])
		var selection = ""
		
		for (var state of arg['selection']){
			selection += state + '\n'
		}

		fs.writeFileSync(arg['file'] + ".txt", selection)
		
		var command = "simple_private_exec"
		var commandargs = []
		commandargs.push("prg=update_project_stateflags")
		commandargs.push("projfile=" + arg['file'])
		commandargs.push("oritype=cls2D")
		commandargs.push("infile=" + arg['file'] + ".txt")

		return spawn(command, commandargs, {capture: ['stdout']})
			.then(() => {
				return({status : "ok"})
			})
			.catch((error) => {
				return({status : "error"})
			})
	}
	
	public saveMicsSelection(modules, arg){
		var spawn = require('child-process-promise').spawn
		fs.copyFileSync(arg['projectfile'], arg['file'])
		var selection = ""
		
		for (var state of arg['selection']){
			selection += state + '\n'
		}

		fs.writeFileSync(arg['file'] + ".txt", selection)
		
		var command = "simple_private_exec"
		var commandargs = []
		commandargs.push("prg=update_project_stateflags")
		commandargs.push("projfile=" + arg['file'])
		commandargs.push("oritype=mic")
		commandargs.push("infile=" + arg['file'] + ".txt")

		return spawn(command, commandargs, {capture: ['stdout']})
			.then(() => {
				return({status : "ok"})
			})
			.catch((error) => {
				return({status : "error"})
			})
	}
	
	public viewParticles2D(modules, arg){
		var spawn = require('child-process-promise').spawn
		var command = "simple_private_exec"
		var commandargs = []
		var classcontents = []
		var stks = []
		commandargs.push("prg=print_project_vals")
		commandargs.push("projfile=" + arg['projfile'])
		commandargs.push("oritype=ptcl2D")
		commandargs.push("keys=class,x,y,dfx,dfy,angast,frameid,stkind,bfac")
		return spawn(command, commandargs, {capture: ['stdout']})
			.then((result) => {
				var lines = result.stdout.split("\n")
				for(var line of lines){
					var elements = line.split((/[ ]+/))
					elements.shift()
					if(Number(elements[2]) == arg['class'] && elements[1] != "0"){
						classcontents.push(elements)
					}
				}
				return
			})
			.then(() => {
				commandargs = []
				commandargs.push("prg=print_project_vals")
				commandargs.push("projfile=" + arg['projfile'])
				commandargs.push("oritype=stk")
				commandargs.push("keys=stk")
				return spawn(command, commandargs, {capture: ['stdout']})
			})
			.then((result) => {
				var lines = result.stdout.split("\n")
				for(var line of lines){
					var elements = line.split((/[ ]+/))
					stks.push(elements[3])
				}
				return
			})
			.then(() => {
				for(var i = 0; i < classcontents.length; i++){
					var stk = stks[Number(classcontents[i][9]) - 1]
					classcontents[i][9] = stk
					
				}
				return({html : this.ptclsview2d({ptcls : classcontents})})
			})
	}
	
	public viewImportMovies(modules, arg){
		var spawn = require('child-process-promise').spawn
		var command = "simple_private_exec"
		var commandargs = []
		var mics = []
		var projectfile = arg['folder'] + "/project.simple"
		commandargs.push("prg=print_project_vals")
		commandargs.push("projfile=" + projectfile)
		commandargs.push("oritype=mic")
		commandargs.push("keys=intg")
		return spawn(command, commandargs, {capture: ['stdout']})
			.then((result) => {
				var lines = result.stdout.split("\n")
				for(var line of lines){
					var elements = line.split((/[ ]+/))
					if(elements[3]){
						mics.push([ elements[3], elements[3].split('\\').pop().split('/').pop()])
					}
				}
				return
			})
			.then(() => {
				return({html : this.importmoviesview({movies : mics, folder : arg['folder'], projectfile : projectfile}), func : "viewer.loadImages('mic')"})
			})
	}
	
	public viewCTFEstimate(modules, arg){
		var spawn = require('child-process-promise').spawn
		var command = "simple_private_exec"
		var commandargs = []
		var fits = []
		var projectfile = arg['folder'] + "/project.simple"
		commandargs.push("prg=print_project_vals")
		commandargs.push("projfile=" + projectfile)
		commandargs.push("oritype=mic")
		commandargs.push("keys=intg,dfx,dfy,angast")
		return spawn(command, commandargs, {capture: ['stdout']})
			.then((result) => {
				var lines = result.stdout.split("\n")
				for(var line of lines){
					var elements = line.split((/[ ]+/))
					if(elements[3]){
						fits.push([arg['folder'] + "/" + elements[3].split('\\').pop().split('/').pop().replace("_intg.mrc", "_ctf_estimate_diag.jpg"), elements[4], elements[5], elements[6]])
					}
				}
				return
			})
			.then(() => {
				return({html : this.ctfview({fits : fits, folder : arg['folder'], projectfile : projectfile}), func : "viewer.loadImages('fits')"})
			})
	}
	
	public viewParticles(modules, arg){
		var spawn = require('child-process-promise').spawn
		var command = "simple_private_exec"
		var commandargs = []
		var stks = []
		commandargs.push("prg=print_project_vals")
		commandargs.push("projfile=" + arg['folder'] + "/project.simple")
		commandargs.push("oritype=stk")
		commandargs.push("keys=stk,nptcls")
		
		return spawn(command, commandargs, {capture: ['stdout']})
			.then((result) => {
				var lines = result.stdout.split("\n")
				for(var line in lines){
					var elements = lines[line].split((/[ ]+/))
					if(elements[3]){
						stks.push([elements[3], elements[3].split('\\').pop().split('/').pop().replace(".mrc",""), elements[4]])
					}
				}
				return({html : this.ptclsview({stks : stks})})
			})
	}
	
	public viewStkParticles(modules, arg){
		var spawn = require('child-process-promise').spawn
		var command = "simple_private_exec"
		var commandargs = []
		var ptcls = []
		var stks = []
		commandargs.push("prg=print_project_vals")
		commandargs.push("projfile=" + arg['folder'] + "/project.simple")
		commandargs.push("oritype=ptcl2D")
		commandargs.push("keys=class,x,y,dfx,dfy,angast,frameid,stkind")
		return spawn(command, commandargs, {capture: ['stdout']})
			.then((result) => {
				var lines = result.stdout.split("\n")
				for(var line of lines){
					var elements = line.split((/[ ]+/))
					elements.shift()
					if(Number(elements[2]) == arg['class'] && elements[1] != "0"){
						ptcls.push(elements)
					}
				}
				return
			})
			.then(() => {
				commandargs = []
				commandargs.push("prg=print_project_vals")
				commandargs.push("projfile=" + arg['folder'] + "/project.simple")
				commandargs.push("oritype=stk")
				commandargs.push("keys=stk")
				return spawn(command, commandargs, {capture: ['stdout']})
			})
			.then((result) => {
				var lines = result.stdout.split("\n")
				for(var line of lines){
					var elements = line.split((/[ ]+/))
					if(elements[3]){
						stks.push([elements[3], elements[3].split('\\').pop().split('/').pop().replace(".mrc","")])
					}
				}
				return
			})
			.then(() => {
				for(var i = 0; i < ptcls.length; i++){
					var stk = stks[Number(ptcls[i][9]) - 1]
					ptcls[i][9] = stk
					
				}
				return({html : this.ptclsview({ptcls : ptcls, stks : stks})})
			})
	}
	
}

module.exports = new Module()