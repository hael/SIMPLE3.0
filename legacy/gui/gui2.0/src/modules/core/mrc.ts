import * as fs from 'fs'
import * as binaryfile from 'binary-file'
import * as sharp from 'sharp'
const {getHeader,toPixels} = require('../../Release/MRChandler')

export default class MRC{

	constructor() {

	}
	
	readHeader(file) {
		console.log("READING " + file)
		return new Promise((resolve, reject) => {
			resolve(getHeader(file));
		})

	/*	var header = {}
		const datain = new binaryfile(file, 'r', true)
		return datain.open()
			.then(function(){
				return datain.read(1024, 0)
			})
			.then(function(data){
				header['data'] = data
				return datain.close()
			})
			.then(function(){
				header['nx'] = header['data'].readInt32LE(0)
				header['ny'] = header['data'].readInt32LE(4)
				header['nz'] = header['data'].readInt32LE(8)
				header['mode'] = header['data'].readInt32LE(12)
				header['nsymbt'] = header['data'].readInt32LE(92)
				return (header)
			})
			.catch(function (err) {
				console.log(`There was an error: ${err}`);
			})*/
	}
	
	readData(file, frame=0) {
		var mrcfile
		var datafile
		return this.readHeader(file)
			.then((data) => {
				mrcfile = data
				datafile = new binaryfile(file, 'r', true)
				return datafile.open()
			})
			.then(() => {
				return datafile.seek(1024 + mrcfile['nsymbt'] + Number(frame) * mrcfile['nx'] * mrcfile['ny'] * 4)
			})
			.then(() => {
				if(mrcfile.mode == 2){
					return datafile.read(mrcfile['nx'] * mrcfile['ny'] * 4, 1024 + mrcfile['nsymbt'] + Number(frame) * mrcfile['nx'] * mrcfile['ny'] * 4)
					
				}
			})
			.then((val) => {
				var elements = mrcfile.nx * mrcfile.ny
				mrcfile['data'] = []
				mrcfile['data'].length = elements
				for(var i = 0; i < elements; i++){
					mrcfile['data'][i] = val.readFloatLE(i * 4)
				}
				return datafile.close()
			})
			.then(() => {
				return(mrcfile)
			})
	}
		
	toJPEG (arg){
		var json = toPixels(arg['stackfile'], arg['frame'])
		return sharp(json['pixbuf'], { raw : {
			width : json['nx'],
			height : json['ny'],
			channels : 1
		}})
			.resize(Number(arg['width']))
			.jpeg()
			.toBuffer()
			.then(function (image) {
				return({image : image})
			})
	}
	
	toJPEGwithBoxes(arg){
		//var json = toPixels(arg['stackfile'], arg['frame'])
		var json = getHeader(arg['stackfile'])
		//var scale = Number(arg['width']) / json['nx'];
		var scale = 512 / json['nx'];
		var padding = Math.floor((json['nx'] - json['ny']) * scale / 2)
	//	var svg = "<svg width='" + Math.floor(json['nx'] * scale) + "' height='" + Math.floor(json['ny'] * scale) + "'>"
		var svg = "<svg width='512' height='512'>"
		var boxes = fs.readFileSync(arg['boxfile'], {encoding : 'utf8'})
		var lines = boxes.split("\n")
		for(var line of lines){
			var elements = line.split((/[ , \t]+/))
			if(elements.length > 2){
				svg += "<rect style='fill:none;stroke:magenta;stroke-width:1' x='" + Number(elements[1]) * scale + "' y='" + ((Number(elements[2]) * scale) + padding) + "' height='" + Number(elements[3]) * scale + "' width='" + Number(elements[3]) * scale + "'/>"
			}
		}
		svg += '</svg>'
		
	/*	return sharp(json['pixbuf'], { raw : {
			width : json['nx'],
			height : json['ny'],
			channels : 1
		}})*/
		return sharp(arg['thumb'])
			.extract({left:511, top:0, width:512, height:512})
			.overlayWith(Buffer.from(svg), {})
		//	.resize(Number(arg['width']))
		//	.jpeg()
			.sharpen()
			.toBuffer()
			.then(function (image) {
				return({image : image})
			})
	}

}