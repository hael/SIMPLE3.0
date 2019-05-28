const fs = require( "fs-extra")
const spawn = require('child-process-promise').spawn
const path = require('path')
const grepit = require('grepit')

const sqlite = require('./sqlite')

class SimpleExec {

  constructor(){}
  
  replaceRelativePath(dir, relpath){
	var fullpath = relpath
	var parentdir = path.dirname(dir)
	if(relpath.includes('../')){
		fullpath = fullpath.replace('..', parentdir)
	}
	else if(relpath.includes('./')){
		fullpath = fullpath.replace('.', dir)
	}
	else if(fullpath.charAt(0) != "/"){
		fullpath = dir + "/" + fullpath
	}
	return fullpath
  }
  
  getProjectInfo(file){
    return fs.stat(file)
    .then(filestat => {
      if(filestat.isFile()){
        var command = "simple_exec"
        var commandargs = ["prg=print_project_info", "projfile=" + file]
        return spawn(command, commandargs, {capture: ['stdout']})
      }else{
        return
      }
    })
  }

  getProjectField(file, oritype){
    return fs.stat(file)
    .then(filestat => {
      if(filestat.isFile()){
        var command = "simple_exec"
        var commandargs = ["prg=print_project_field", "projfile=" + file, "oritype=" + oritype]
        return spawn(command, commandargs, {capture: ['stdout']})
      }else{
        return
      }
    })
  }

  getProjectVals(file, oritype, keys){  
    return fs.stat(file)
    .then(filestat => {
      if(filestat.isFile()){
        var command = "simple_private_exec"
        var commandargs = [
          "prg=print_project_vals",
          "projfile=" + file,
          "oritype=" + oritype,
          "keys=" + keys,
        ]
        return spawn(command, commandargs, {capture: ['stdout']})
      }else{
        return
      }
    })
  }
  
  valsToArray(text){
	  return new Promise((resolve, reject) => {
		  var returnarray = []
		  for(var line of text.split('\n')){
			  var arrayelement = {}
			  for(var element of line.split(" ")){
				  if(element.includes("=")){
					  var keyval = element.split("=")
					  arrayelement[keyval[0]] = keyval[1]
				  }
			  }
			  if(Object.keys(arrayelement).length > 0){
				returnarray.push(arrayelement)
			  }
		  }
		  resolve(returnarray)
	  })
  }
  
  createProject(name, folder){
	  return(spawn("simple_exec", ["prg=new_project", "projname=" + name], {cwd: folder, capture: ['stdout']}))
  }
  
  createCavgs(projfile){
	  console.log(path.dirname(projfile) + '/selected_clusters.mrc')
	  return(spawn("simple_private_exec", ["prg=export_cavgs", "projfile=" + projfile, "outstk=" + path.dirname(projfile) + '/selected_clusters.mrc'], {cwd: path.dirname(projfile), capture: ['stdout']}))
  }
  
  relionExport(projfile){
	var dir = path.dirname(projfile) + '_RELION'
	var micrographspresent = false
	var particlespresent = false
	var mics = []
	var stks = []
	var ptcls2D = []
	
	return fs.ensureDir(dir)
	.then(() => {
	  return this.getProjectInfo(projfile)
	})
	.then(projinfo => {
		micrographspresent = (projinfo.stdout.includes('mic')) ? true : false
		particlespresent = (projinfo.stdout.includes('ptcl2D')) ? true : false
		return
	})
	.then(() => {
		if(micrographspresent){
			return fs.ensureDir(dir + '/micrographs')
			.then(() => {
				return this.getProjectField(projfile, 'mic')
			})
			.then(projvals => {
				return this.valsToArray(projvals.stdout)
			})
			.then(projvalarray => {
				mics = projvalarray
				var promises = []
				for(var mic of mics){
					promises.push(fs.symlink(this.replaceRelativePath(path.dirname(projfile), mic['intg']), dir + '/micrographs/' + path.basename(mic['intg'])))
				}
				return Promise.all(promises)
			})
		}else{
			return
		}
	})
	.then(() => {
		if(particlespresent){
			return fs.ensureDir(dir + '/particles')
			.then(() => {
				return this.getProjectField(projfile, 'stk')
			})
			.then(projvals => {
				return this.valsToArray(projvals.stdout)
			})
			.then(projvalarray => {
				stks = projvalarray
				var promises = []
				for(var stk of stks){
					promises.push(fs.symlink(this.replaceRelativePath(path.dirname(projfile), stk['stk']), dir + '/particles/' + path.basename(stk['stk']) + 's'))
				}
				return Promise.all(promises)
			})
			.then(() => {
				return this.getProjectField(projfile, 'ptcl2D')
			})
			.then(projvals => {
				return this.valsToArray(projvals.stdout)
			})
			.then(projvalarray => {
				ptcls2D = projvalarray
				return
			})
			.then(() => {
				for(var i in stks){
					stks[i]['stackcount'] = 0
				}
				return
			})
		}else{
			return
		}
	})
	.then(() => {
		var attributes = []
		var starfile = ""
        starfile += "data_\n"
        starfile += "loop_\n"
        
        if(micrographspresent){
			starfile += "_rlnMicrographName\n"
			attributes.push(['mic', 'intg'])
		}
		
		if(particlespresent){
			starfile += "_rlnImageName\n"
			attributes.push(['stk', 'stk'])
		}
		
		if(mics[0] != undefined && mics[0]['dfx'] != undefined){
			starfile += "_rlnDefocusU\n"
			attributes.push(['mic', 'dfx'])
		}else if(stks[0] != undefined && stks[0]['dfx'] != undefined){
			starfile += "_rlnDefocusU\n"
			attributes.push(['stk', 'dfx'])
		}else if(ptcls2D[0] != undefined && ptcls2D[0]['dfx'] != undefined){
			starfile += "_rlnDefocusU\n"
			attributes.push(['ptcl2D', 'dfx'])
		}
		
		if(mics[0] != undefined && mics[0]['dfy'] != undefined){
			starfile += "_rlnDefocusV\n"
			attributes.push(['mic', 'dfy'])
		}else if(stks[0] != undefined && stks[0]['dfy'] != undefined){
			starfile += "_rlnDefocusV\n"
			attributes.push(['stk', 'dfy'])
		}else if(ptcls2D[0] != undefined && ptcls2D[0]['dfx'] != undefined){
			starfile += "_rlnDefocusV\n"
			attributes.push(['ptcl2D', 'dfy'])
		}
	
		if(mics[0] != undefined && mics[0]['angast'] != undefined){
			starfile += "_rlnDefocusAngle\n"
			attributes.push(['mic', 'angast'])
		}else if(stks[0] != undefined && stks[0]['angast'] != undefined){
			starfile += "_rlnDefocusAngle\n"
			attributes.push(['stk', 'angast'])
		}else if(ptcls2D[0] != undefined && ptcls2D[0]['angast'] != undefined){
			starfile += "_rlnDefocusAngle\n"
			attributes.push(['ptcl2D', 'angast'])
		}
		
		if(mics[0] != undefined && mics[0]['kv'] != undefined){
			starfile += "_rlnVoltage\n"
			attributes.push(['mic', 'kv'])
		}else if(stks[0] != undefined && stks[0]['kv'] != undefined){
			starfile += "_rlnVoltage\n"
			attributes.push(['stk', 'kv'])
		}else if(ptcls2D[0] != undefined && ptcls2D[0]['kv'] != undefined){
			starfile += "_rlnVoltage\n"
			attributes.push(['ptcl2D', 'kv'])
		}
		
		if(mics[0] != undefined && mics[0]['cs'] != undefined){
			starfile += "_rlnSphericalAberration\n"
			attributes.push(['mic', 'cs'])
		}else if(stks[0] != undefined && stks[0]['cs'] != undefined){
			starfile += "_rlnSphericalAberration\n"
			attributes.push(['stk', 'cs'])
		}else if(ptcls2D[0] != undefined && ptcls2D[0]['cs'] != undefined){
			starfile += "_rlnSphericalAberration\n"
			attributes.push(['ptcl2D', 'cs'])
		}
		
		if(mics[0] != undefined && mics[0]['fraca'] != undefined){
			starfile += "_rlnAmplitudeContrast\n"
			attributes.push(['mic', 'fraca'])
		}else if(stks[0] != undefined && stks[0]['fraca'] != undefined){
			starfile += "_rlnAmplitudeContrast\n"
			attributes.push(['stk', 'fraca'])
		}else if(ptcls2D[0] != undefined && ptcls2D[0]['fraca'] != undefined){
			starfile += "_rlnAmplitudeContrast\n"
			attributes.push(['ptcl2D', 'fraca'])
		}
		
		if(mics[0] != undefined && mics[0]['smpd'] != undefined){
			starfile += "_rlnMagnification\n"
			starfile += "_rlnDetectorPixelSize\n"
			attributes.push(['mic', 'smpd'])
			attributes.push(['mic', 'mag'])
		}else if(stks[0] != undefined && stks[0]['smpd'] != undefined){
			starfile += "_rlnMagnification\n"
			starfile += "_rlnDetectorPixelSize\n"
			attributes.push(['stk', 'smpd'])
			attributes.push(['stk', 'mag'])
		}else if(ptcls2D[0] != undefined && ptcls2D[0]['smpd'] != undefined){
			starfile += "_rlnMagnification\n"
			starfile += "_rlnDetectorPixelSize\n"
			attributes.push(['ptcl2D', 'mag'])
			attributes.push(['ptcl2D', 'smpd'])
		}
		
		if(ptcls2D[0] != undefined && ptcls2D[0]['xpos'] != undefined){
			starfile += "_rlnCoordinateX\n"
			attributes.push(['ptcl2D', 'xpos'])
		}
		
		if(ptcls2D[0] != undefined && ptcls2D[0]['ypos'] != undefined){
			starfile += "_rlnCoordinateY\n"
			attributes.push(['ptcl2D', 'ypos'])
		}
		
		var filename
		if(micrographspresent == true && particlespresent == false){
			filename = 'micrographs.star'
			for(var mic of mics){
				if(Number(mic['state']) > 0){
					for(var attribute of attributes){
						var rawvalue
						if(attribute[0] == 'mic'){
							rawvalue = 'micrographs/' + path.basename(mic[attribute[1]])
						}
						if(attribute[1] == 'dfx' || attribute[1] == 'dfy'){
							rawvalue = Number(rawvalue) * 10000
						}else if(attribute[1] == 'mag'){
							rawvalue = 10000
						}
						starfile += rawvalue + ' '
					}
					starfile += '\n'
				}
			}
		}else if (particlespresent == true && micrographspresent == true) {
			filename = 'particles.star'
			for (var ptclind in ptcls2D){
				var stkind = Number(ptcls2D[ptclind]['stkind']) - 1
				stks[stkind]['stackcount']++
				var micrograph 
				var base = path.basename(stks[stkind]['stk']).replace("ptcls_from_", "")
				
				for(var mic of mics){
					if(mic['intg'].includes(base)){
						micrograph = mic
						break
					}
				}
				
				if(Number(ptcls2D[ptclind]['state']) > 0){
					for(var attribute of attributes){
						var rawvalue
						if(attribute[0] == 'stk'){
							rawvalue = stks[stkind][attribute[1]]
						}else if (attribute[0] == 'mic'){
							rawvalue = mic[attribute[1]]
						}else if (attribute[0] == 'ptcl2D'){
							rawvalue = ptcls2D[ptclind][attribute[1]]
						}else if (attribute[0] == 'mic'){
							rawvalue = micrograph[attribute[1]]
						}
						if(attribute[1] == 'stk'){
							rawvalue = stks[stkind]['stackcount'] +'@particles/' + path.basename(rawvalue) + 's'
						}else if(attribute[1] == 'intg'){
							rawvalue = 'micrographs/' + path.basename(rawvalue)
						}else if(attribute[1] == 'dfx' || attribute[1] == 'dfy'){
							rawvalue = Number(rawvalue) * 10000
						}else if(attribute[1] == 'mag'){
							rawvalue = 10000
						}else if (attribute[1] == 'xpos' || attribute[1] == 'ypos'){
							rawvalue = Number(rawvalue) + (Number(stks[stkind]['box']) / 2)
						}
						
						starfile += rawvalue + ' '
					}
					starfile += '\n'
				}
			}
		}else if (particlespresent == true && micrographspresent == false) {
			filename = 'particles.star'
			for (var ptclind in ptcls2D){
				var stkind = Number(ptcls2D[ptclind]['stkind']) - 1
				stks[stkind]['stackcount']++
				if(Number(ptcls2D[ptclind]['state']) > 0){
					for(var attribute of attributes){
						var rawvalue
						if(attribute[0] == 'stk'){
							rawvalue = stks[stkind][attribute[1]]
						}else if (attribute[0] == 'ptcl2D'){
							rawvalue = ptcls2D[ptclind][attribute[1]]
						}
						if(attribute[1] == 'stk'){
							rawvalue = stks[stkind]['stackcount'] +'@particles/' + path.basename(rawvalue) + 's'
							
						}else if(attribute[1] == 'dfx' || attribute[1] == 'dfy'){
							rawvalue = Number(rawvalue) * 10000
						}else if(attribute[1] == 'mag'){
							rawvalue = 10000
						}
						
						starfile += rawvalue + ' '
					}
					starfile += '\n'
				}
			}
		}
		return fs.writeFile(dir + '/' + filename, starfile, 'utf8')
	})
	.catch(err => {
	  console.log(err)
	})
  }

  getCommandArgs(arg){
		return new Promise ((resolve, reject) => {
			var commandargs = ["prg=" + arg['type']]
			var environmentargs = ['prg=update_project']

			for(var key of Object.keys(arg['keys'])){
			  if(arg['keys'][key]!= "" && !key.includes('keyenv')){
				if(arg['keys'][key] == "true"){
				  commandargs.push(key.replace('key', '') + "=yes")
				}else if(arg['keys'][key] == "false"){
				  commandargs.push(key.replace('key', '') + "=no")
				}else{
				  commandargs.push(key.replace('key', '') + "=" + arg['keys'][key])
				}
			  } else if (arg['keys'][key] != "" && key.includes('keyenv')){
				environmentargs.push(key.replace('keyenv', '') + "=" + arg['keys'][key])
			  }
			}
			if(arg['projfile']){
				commandargs.push("projfile=" + arg['projfile'])
				environmentargs.push("projfile=" + arg['projfile'])
			}
			resolve([commandargs, environmentargs])
		})
	}
	
	createDir(arg){
		var commandargs
		this.jobid = false
		return this.getCommandArgs(arg)
		.then(commandarguments => {
			return sqlite.sqlQuery("INSERT into " + arg['projecttable'] + " (name, description, arguments, status, view, type, parent, folder) VALUES ('" + arg['name'] + "','" + arg['description'] + "','" + JSON.stringify(arg) + "','running', '" + JSON.stringify(arg['view']) + "', '" + arg['type'] + "', '" + arg['projfile'] + "', 'null')")
		})
		.then(rows => {
			return sqlite.sqlQuery("SELECT seq FROM sqlite_sequence WHERE name='" + arg['projecttable'] + "'")
		})
		.then(rows => {
			this.jobid = rows[0]['seq']
			console.log('JOBID', this.jobid)
			console.log(arg['projectfolder'] + '/' + this.jobid + '_' + arg['type'])
			return fs.mkdir(arg['projectfolder'] + '/' + this.jobid + '_' + arg['type'])
		})
		.then(() => {
			return sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET folder='" + arg['projectfolder'] + "/" + this.jobid + '_' + arg['type'] + "' WHERE id=" + this.jobid)
		})
		.then(() => {	
			return sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Finished' WHERE id=" + this.jobid)
		})
		.then(() => {
			return fs.copyFile(arg['projfile'], arg['projectfolder'] + '/' + this.jobid + '_' + arg['type'] + '/' + arg['projfile'].split('/').pop())
		})
	}
	
/*	exec(arg, jobid){
		this.execdir = false
		var commandargs
		return this.getCommandArgs(arg)
		.then(commandarguments => {
			commandargs = commandarguments
			return spawn("simple_exec", commandargs[1], {cwd: arg['projectfolder']})
		})
		.then(output => {
			var promise = spawn("simple_exec", commandargs[0], {cwd: arg['projectfolder']})
			var executeprocess = promise.childProcess
			executeprocess.on('exit', code => {
				console.log(`child process exited with code ${code}`);
				if(arg['saveclusters']){
					console.log(`writing cavgs`);
					this.createCavgs(this.execdir + '/' + path.basename(arg['projfile']))
				}
				if(arg['savestar']){
					console.log(`exporting to relion`);
					this.relionExport(this.execdir + '/' + path.basename(arg['projfile']))
				}
				if(code !== null && code == 0){
					sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Finished' WHERE id=" + jobid)
				}else{
					sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Error' WHERE id=" + jobid)
				}
			})
			executeprocess.on('error', error => {
				console.log(`child process exited with error ${error}`)
				if(this.execdir){
					fs.appendFile(this.execdir + '/simple.log', error.toString())
				}
				sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Error' WHERE id=" + jobid)
			})
			executeprocess.stdout.on('data', data => {
				if(!this.execdir){
					var lines = data.toString().split("\n")
					for (var line of lines){
						if(line.includes("EXECUTION DIRECTORY")){
							this.execdir = arg['projectfolder'] + "/" + line.split(" ").pop()
							sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET folder='" + arg['projectfolder'] + "/" + line.split(" ").pop() + "' WHERE id=" + jobid)
							break
						}
					}
				}
				if(this.execdir){
					fs.appendFile(this.execdir + '/simple.log', data.toString())
				}

			})
			console.log(`Spawned child pid: ${executeprocess.pid}`)
			return Promise.all([promise])
		})
		.then(() =>{
			return new Promise(resolve => setTimeout(resolve, 10000))
		})
	}*/
	
	exec(arg){
		this.execdir = false
		this.jobid = false
		var commandargs
		return this.getCommandArgs(arg)
		.then(commandarguments => {
			commandargs = commandarguments
			return spawn("simple_exec", commandargs[1], {cwd: arg['projectfolder']})
		})
		.then(output => {
			var promise = spawn("simple_exec", commandargs[0], {cwd: arg['projectfolder']})
			var executeprocess = promise.childProcess
	/*		executeprocess.on('exit', code => {
				console.log(`child process exited with code ${code}`);
				if(code !== null && code == 0){
					sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Finished' WHERE id=" + this.jobid)
				}else{
					sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Error' WHERE id=" + this.jobid)
				}
			})*/
		/*	executeprocess.on('error', error => {
				console.log(`child process exited with error ${error}`)
				if(this.execdir){
					fs.appendFile(this.execdir + '/simple.log', error.toString())
				}
				console.log("UPDATE " + arg['projecttable'] + " SET status='Error' WHERE id=" + this.jobid)
				sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Error' WHERE id=" + this.jobid)
			})*/
			executeprocess.stdout.on('data', data => {
				var lines = data.toString().split("\n")
				if(!this.execdir){
					for (var line of lines){
						if(line.includes("EXECUTION DIRECTORY")){
							this.execdir = arg['projectfolder'] + "/" + line.split(" ").pop()
							sqlite.sqlQuery("INSERT into " + arg['projecttable'] + " (name, description, arguments, status, view, type, parent, folder) VALUES ('" + arg['name'] + "','" + arg['description'] + "','" + JSON.stringify(arg) + "','running', '" + JSON.stringify(arg['view']) + "', '" + arg['type'] + "', '" + arg['projfile'] + "', '" + this.execdir + "')")
							.then(rows => {
								return sqlite.sqlQuery("SELECT seq FROM sqlite_sequence WHERE name='" + arg['projecttable'] + "'")
							})
							.then(rows => {
								this.jobid = rows[0]['seq']
								console.log('JOBID', this.jobid)
							})
							break
						}
					}
				}
				if(this.execdir){
					fs.appendFile(this.execdir + '/simple.log', data.toString())
				}
			})
			console.log(`Spawned child pid: ${executeprocess.pid}`)
			return Promise.all([promise])
		})
		.then(output =>{
			return new Promise((resolve, reject) => {
				var interval = setInterval(() => { 
					console.log('interval')
					if(this.execdir){
						console.log('exwecdir', this.execdir)
						clearInterval(interval)
						clearTimeout(timeout)
						if(arg['saveclusters']){
							console.log('clusters')
							resolve (this.createCavgs(this.execdir + '/' + path.basename(arg['projfile'])))
						}else{
							resolve
						}
					}
				}, 1000)
				var timeout = setTimeout(() => {
					console.log('timeout')
					clearInterval(interval)
					clearTimeout(timeout)
					resolve
				}, 20000)
			})
		})

		})
		.then(() =>{
				if(arg['savestar']){
					console.log(`exporting to relion`);
					return this.relionExport(this.execdir + '/' + path.basename(arg['projfile']))
				}else{
					return
				}
		})
	/*	.then(() =>{
			return new Promise(resolve => {
				var interval = setInterval(() => { 
					console.log("Hello")
					if(this.jobid && this.execdir){
						clearInterval(interval)
						clearTimeout(timeout)
						resolve({})
					}
				}, 3000)
				var timeout = setTimeout(() => {
					console.log("timout")
					clearInterval(interval)
					clearTimeout(timeout)
					resolve({})
				}, 10000)
			})
		})*/
	}
	
/*	
	distrExec(arg, jobid){
		this.execdir = false
		var commandargs
		return this.getCommandArgs(arg)
		.then(commandarguments => {
			commandargs = commandarguments
			return spawn("simple_exec", commandargs[1], {cwd: arg['projectfolder']})
		})
		.then(output => {
			var promise = spawn("simple_distr_exec", commandargs[0], {cwd: arg['projectfolder']})
			var executeprocess = promise.childProcess
			executeprocess.on('exit', code => {
				console.log(`child process exited with code ${code}`);
				if(code !== null && code == 0){
					sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Finished' WHERE id=" + jobid)
				}else{
					sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Error' WHERE id=" + jobid)
				}
			})
			executeprocess.on('error', error => {
				console.log(`child process exited with error ${error}`)
				if(this.execdir){
					fs.appendFile(this.execdir + '/simple.log', error.toString())
				}
				sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Error' WHERE id=" + jobid)
			})
			executeprocess.stdout.on('data', data => {
				console.log(data.toString())
				if(!this.execdir){
					var lines = data.toString().split("\n")
					for (var line of lines){
						if(line.includes("EXECUTION DIRECTORY")){
							this.execdir = arg['projectfolder'] + "/" + line.split(" ").pop()
							sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET folder='" + arg['projectfolder'] + "/" + line.split(" ").pop() + "' WHERE id=" + jobid)
							break
						}
					}
				}
				
				if(this.execdir){
					fs.appendFile(this.execdir + '/simple.log', data.toString())
				}

			})
			console.log(`Spawned child pid: ${executeprocess.pid}`)
			return Promise.all([promise])
		})
		.then(() =>{
			return new Promise(resolve => setTimeout(resolve, 10000))
		})
	}
*/

	distrExec(arg){
		this.execdir = false
		this.jobid = false
		var commandargs
		return this.getCommandArgs(arg)
		.then(commandarguments => {
			commandargs = commandarguments
			return spawn("simple_exec", commandargs[1], {cwd: arg['projectfolder']})
		})
		.then(output => {
			var promise = spawn("simple_distr_exec", commandargs[0], {cwd: arg['projectfolder']})
			var executeprocess = promise.childProcess
	/*		executeprocess.on('exit', code => {
				console.log(`child process exited with code ${code}`);
				if(code !== null && code == 0){
					sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Finished' WHERE id=" + this.jobid)
				}else{
					
					sqlite.sqlQuery("UPDATE " + arg['projecttable'] + " SET status='Error' WHERE id=" + this.jobid)
				}
			})*/
			/*executeprocess.on('error', error => {
				console.log(`child process exited with error ${error}`)
				if(this.execdir){
					fs.appendFile(this.execdir + '/simple.log', error.toString())
				}
			})*/
			executeprocess.stdout.on('data', data => {
				var lines = data.toString().split("\n")
				if(!this.execdir){
					for (var line of lines){
						if(line.includes("EXECUTION DIRECTORY")){
							this.execdir = arg['projectfolder'] + "/" + line.split(" ").pop()
							sqlite.sqlQuery("INSERT into " + arg['projecttable'] + " (name, description, arguments, status, view, type, parent, folder) VALUES ('" + arg['name'] + "','" + arg['description'] + "','" + JSON.stringify(arg) + "','running', '" + JSON.stringify(arg['view']) + "', '" + arg['type'] + "', '" + arg['projfile'] + "', '" + this.execdir + "')")
							.then(rows => {
								return sqlite.sqlQuery("SELECT seq FROM sqlite_sequence WHERE name='" + arg['projecttable'] + "'")
							})
							.then(rows => {
								this.jobid = rows[0]['seq']
								console.log('JOBID', this.jobid)
							})
							break
						}
					}
				}
				if(this.execdir){
					fs.appendFile(this.execdir + '/simple.log', data.toString())
				}
			})
			console.log(`Spawned child pid: ${executeprocess.pid}`)
			return Promise.all([promise])
		})
		.then(output =>{
			return new Promise((resolve, reject) => {
				var interval = setInterval(() => { 
					console.log('interval')
					if(this.execdir){
						console.log('exwecdir', this.execdir)
						clearInterval(interval)
						clearTimeout(timeout)
						if(arg['saveclusters']){
							console.log('clusters')
							resolve (this.createCavgs(this.execdir + '/' + path.basename(arg['projfile'])))
						}else{
							resolve
						}
					}
				}, 1000)
				var timeout = setTimeout(() => {
					console.log('timeout')
					clearInterval(interval)
					clearTimeout(timeout)
					resolve
				}, 20000)
			})
		})
		.then(() =>{
				if(arg['savestar']){
					console.log(`exporting to relion`);
					return this.relionExport(this.execdir + '/' + path.basename(arg['projfile']))
				}else{
					return
				}
		})
	}	
/*
  taskSimple(arg, taskinfo, commandargs, compenvargs){
    var out
    return new Promise ((resolve, reject) => {
      if(arg['inputpath'] != "undefined" && arg['inputpath'] != ""){
        resolve (fs.ensureDir(taskinfo['jobfolder'] + "/project")
          .then(() => { 
            return(fs.copyFile(arg['inputpath'], taskinfo['jobfolder'] + "/project/project.simple"))
          })
        )
      } else {
        resolve (spawn("simple_exec", ["prg=new_project", "projname=project"], {cwd: taskinfo['jobfolder'], stdio: ['ignore', out, out ]}))
      }
    })
    .then(() => {
      return fs.open(taskinfo['jobfolder'] + '/task.log', 'a')
    })
    .then(outfile => {
      out = outfile
      return spawn("simple_exec", compenvargs, {cwd: taskinfo['jobfolder'], stdio: ['ignore', out, out ]})
    })
    .then(() => {
      return fs.rename(taskinfo['jobfolder'] + "/project/project.simple", taskinfo['jobfolder'] + "/project.simple")
    })
    .then(() => {
      var promise = spawn(arg['executable'], commandargs, {detached: true, cwd: taskinfo['jobfolder'], stdio: [ 'ignore', out, out ]})
      var executeprocess = promise.childProcess
      executeprocess.on('exit', code => {
        console.log(`child process exited with code ${code}`);
        if(code !== null && code == 0){
          global.modules['available']['core']['updateStatus'](arg['projecttable'], taskinfo['jobid'], "Finished")
        }else{
          global.modules['available']['core']['updateStatus'](arg['projecttable'], taskinfo['jobid'], "Error")
        }
      })
      executeprocess.on('error', error => {
        console.log(`child process exited with error ${error}`)
        global.modules['available']['core']['updateStatus'](arg['projecttable'], taskinfo['jobid'], "Error")
      })
      console.log(`Spawned child pid: ${executeprocess.pid}`)
      return global.modules['available']['core']['updatePid'](arg['projecttable'], taskinfo['jobid'], executeprocess.pid)
    })
    .then(() => {
      return fs.close(out)
    })
  }

  taskImport(arg, taskinfo, compenvargs){
    var out
    var rootname = path.basename(arg['inputpath'], ".simple")
    var rootpath = path.dirname(arg['inputpath'])
    compenvargs.push('projfile=' + rootname + "/" + rootname + ".simple")
    return fs.rmdir(taskinfo['jobfolder'])
    .then(() => {
      return fs.symlink(rootpath, taskinfo['jobfolder'])
    })
    .then(() => {
      return fs.mkdir(taskinfo['jobfolder'] + "/" + rootname)
    })
    .then(() => {
      return fs.copyFile(arg['inputpath'], taskinfo['jobfolder'] + "/" + rootname + "/" + rootname + ".simple")
    })
    .then(() => {
      return fs.open(taskinfo['jobfolder'] + '/task.log', 'a')
    })
    .then((outfile) => {
      out = outfile
      return spawn("simple_exec", compenvargs, {cwd: taskinfo['jobfolder'], stdio: ['ignore', out, out]})
    })
    .then(() => {
      return fs.close(out)
    })
    .then(() => {
      return fs.rename(taskinfo['jobfolder'] + "/" + rootname + "/project.simple", taskinfo['jobfolder'] + "/project.simple")
    })
    .then(() => {
      return global.modules['available']['core']['updateStatus'](arg['projecttable'], taskinfo['jobid'], "Imported")
    })
  }

  execute(arg){
    var commandargs = ["prg=" + arg['type'], "mkdir=no"]
    var compenvargs = ['prg=update_project', 'projname=project']

    for(var key of Object.keys(arg['keys'])){
      if(arg['keys'][key]!= "" && !key.includes('keyenv')){
        if(arg['keys'][key] == "true"){
          commandargs.push(key.replace('key', '') + "=yes")
        }else if(arg['keys'][key] == "false"){
          commandargs.push(key.replace('key', '') + "=no")
        }else{
          commandargs.push(key.replace('key', '') + "=" + arg['keys'][key])
        }
      } else if (arg['keys'][key] != "" && key.includes('keyenv')){
        compenvargs.push(key.replace('keyenv', '') + "=" + arg['keys'][key])
      }
    }

    if(arg['type'] == "import"){
        arg['type'] = arg['keys']['keyjob_type']
    }

    arg['view'] = this.attachViews(arg['type'])

    return modules['available']['core']['taskCreate'](arg)
    .then(taskinfo => {
      if(arg['executable'] == "simple_import"){
        this.taskImport(arg, taskinfo, compenvargs)
      } else {
        this.taskSimple(arg, taskinfo, commandargs, compenvargs)
      }
      return{folder: taskinfo['jobfolder']}
    })
  }
*/
}

module.exports = new SimpleExec()
