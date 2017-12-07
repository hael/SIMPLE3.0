function getAjax (url, success) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState>3 && xhr.status==200){
			success(xhr.responseText);
		}
    };
    xhr.send();
}

function postAjax (url, success) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', url, true);
    xhr.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
    xhr.onreadystatechange = function() {
        if (xhr.readyState>3 && xhr.status==200){
			success(xhr.responseText);
		}
    };
    xhr.send();
}

function setTitle() {
	document.getElementById('headerproject').value = window.location.toString().split('?')[2];
}

function getFileviewerData () {
	var fileviewerfilename = document.getElementById('fileviewerfilename').value;
	getAjax('JSONhandler?function=unblurview&' + window.location.toString().split('?')[1], function(data){showFileViewerData(data)});
}
 
function showProjectHistory(){
	var mainpaneiframe = parent.document.getElementById('mainpaneiframe');
	mainpaneiframe.src = "projecthistory.html"
}

function showFileViewerData (data){
	var JSONdata = JSON.parse(data);
	
	var rootdirectory = document.getElementById('rootdirectory');
	rootdirectory.value = JSONdata.rootdirectory;
	
	var saveselectionfolder = document.getElementById('saveselectionfolder');
	saveselectionfolder.value = JSONdata.rootdirectory;
	
	var inputfilename = document.getElementById('inputfilename');
	inputfilename.value = JSONdata.inputfilename;

	var snapshots = document.getElementById('snapshots');
	for (var i = 0; i < JSONdata.snapshots.length; i++) {
		var div = document.createElement("div");
		div.className = 'snapshot';
		if(JSONdata.snapshots[i]['state'] == "0"){
			div.setAttribute('data-selected', "no");
		} else{
			div.setAttribute('data-selected', "yes");
		}
		div.setAttribute('data-rootdirectory', JSONdata.rootdirectory);
		div.onclick = function() {
			selectUnselectSnapshot(this);
		}
		var attributesdiv = document.createElement("div");
		attributesdiv.className = 'attributes';
		
		var keys = Object.keys(JSONdata.snapshots[0]);
		for(var j = 0; j < keys.length; j++) {
			div.setAttribute('data-'+keys[j], JSONdata.snapshots[i][keys[j]]);
			var attributediv = document.createElement("div");
			attributediv.innerHTML = keys[j];
			attributediv.innerHTML += " : ";
			attributediv.innerHTML += JSONdata.snapshots[i][keys[j]];
			attributesdiv.appendChild(attributediv);
		}
		
		div.setAttribute('data-id', JSONdata.snapshots[i].id);
		div.setAttribute('data-frameid', 0);

		div.appendChild(attributesdiv);
		var gauze = document.createElement("div");
		gauze.className = "snapshotgauze";
		if(JSONdata.snapshots[i]['state'] == "0"){
			gauze.style.display = "block";
		} 
		div.appendChild(gauze);
		snapshots.appendChild(div);
	} 
	updateFileViewer();
}


function updateFileViewer () {
	var snapshots = document.getElementsByClassName('snapshot');
	var selecteddisplayoptions = document.getElementsByClassName('selecteddisplayoptions');
	for (var i = 0; i < snapshots.length; i++){
		var images = snapshots[i].getElementsByTagName('img');
		for (var j = 0; j < images.length; j++){
			images[j].parentNode.removeChild(images[j]);
		}
		
		var fileimg = document.createElement("img");
		fileimg.src = "img/ctf.png";
		fileimg.className = "snapshotattributesbutton";
		fileimg.onclick = function(e){
			if (!e) var e = window.event;
			e.cancelBubble = true;
			if (e.stopPropagation) e.stopPropagation();
			var attributes = this.parentNode.getElementsByClassName('attributes')[0];
			if(attributes.style.visibility =="visible"){
				attributes.style.visibility = "hidden"
			}else{
				attributes.style.visibility = "visible";
			}
		};

		var rootdirectory = snapshots[i].getAttribute('data-rootdirectory');
		var thumbnail = snapshots[i].getAttribute('data-thumb');
		var ctffindfit= snapshots[i].getAttribute('data-ctffindfit');
		var pspec = snapshots[i].getAttribute('data-pspec');
		
		if(!!thumbnail){
			var img = document.createElement("img");
			img.setAttribute('data-src',"JPEGhandler?filename=" + rootdirectory + "/" +  thumbnail + "&contrast=2&brightness=128&size=200&frameid=0&size=200");
			img.style.width = "200px";
			img.style.height = "200px";
			img.className = 'data-thumb';
			img.alt = "Loading ...";
			img.setAttribute('data-frameid', 0);
			img.id =  rootdirectory + "/" + thumbnail;
			img.oncontextmenu = function(){
				var controlstarget = document.getElementById('controlstarget');
				controlstarget.value = this.className;
				showHideControlsPopup();
				return false;
			}
			snapshots[i].appendChild(img);
		}
		
		if(!!pspec){
			var img = document.createElement("img");
			img.setAttribute('data-src',"JPEGhandler?filename=" + rootdirectory + "/" + pspec  + "&contrast=2&brightness=128&size=200&frameid=0&size=200");
			img.style.width = "200px";
			img.style.height = "200px";
			img.className = 'data-pspec';
			img.alt = "Loading ...";
			img.setAttribute('data-frameid', 0);
			img.id =  rootdirectory + "/" + pspec;
			img.oncontextmenu = function(){
				var controlstarget = document.getElementById('controlstarget');
				controlstarget.value = this.className;
				showHideControlsPopup();
				return false;
			}
			snapshots[i].appendChild(img);
		}
		
		if(!!ctffindfit){
			var img = document.createElement("img");
			img.setAttribute('data-src',"JPEGhandler?filename=" + rootdirectory + "/" +  ctffindfit + "&contrast=2&brightness=128&size=200&frameid=0&size=200");
			img.style.width = "200px";
			img.style.height = "200px";
			img.className = 'data-ctffindfit';
			img.alt = "Loading ...";
			img.setAttribute('data-frameid', 0);
			img.id =  rootdirectory + "/" + ctffindfit;
			img.oncontextmenu = function(){
				var controlstarget = document.getElementById('controlstarget');
				controlstarget.value = this.className;
				showHideControlsPopup();
				return false;
			}
			snapshots[i].appendChild(img);
		}
	}

	document.getElementById('snapshots').addEventListener('scroll', function(){loadImages2()});
	loadImages2();
}

function loadImages(){
	//var unloaded = document.querySelectorAll('[data-loaded="no"]')[0];
	var unloaded = document.querySelectorAll('[data-show="yes"]')[0];
	unloaded.removeAttribute('data-show');
	unloaded.addEventListener('load', loadImages)
	unloaded.src = unloaded.getAttribute('data-src');
}

function loadImages2(){

	var snapshots = document.getElementsByClassName('snapshot');
	var pane = document.getElementById('snapshots');
	paneBoundingClientRect = pane.getBoundingClientRect();
	var topcutoff = paneBoundingClientRect.top;
	var bottomcutoff = paneBoundingClientRect.bottom + (paneBoundingClientRect.bottom - paneBoundingClientRect.top);
	for (var i = 0; i < snapshots.length; i++){
		var snapshotBoundingClientRect = snapshots[i].getBoundingClientRect();
		var images = snapshots[i].getElementsByTagName('img');
		if(snapshotBoundingClientRect.bottom > topcutoff && snapshotBoundingClientRect.top < bottomcutoff) {
			for (var j = 0; j < images.length; j++){
				images[j].setAttribute('data-show',"yes");
			}
		} else 	{
			for (var j = 0; j < images.length; j++){
				images[j].removeAttribute('src');
				images[j].removeAttribute('data-show');
				images[j].removeEventListener("load", loadImages);
			}
		}
	}
	loadImages();
}

function updateControls () {
	var controlstarget = document.getElementById('controlstarget');
	var images = document.getElementsByClassName(controlstarget.value);
	var brightness = document.getElementById('brightness').value;
	var contrast = document.getElementById('contrast').value;
	
	for (var i = 0; i < images.length; i++){
		images[i].setAttribute('data-loaded',"no");
		
		images[i].setAttribute('data-src', "JPEGhandler?filename=" + images[i].id + "&contrast=" + contrast + "&brightness=" + brightness + "&frameid=" + images[i].getAttribute('data-frameid'));
	}
	showHideControlsPopup();
	loadImages2();
}

function showHideHeaderMenu (element) {
	var headermenu = element.parentNode.parentNode.getElementsByClassName('headermenu')[0];
	if (headermenu.style.display == "block") {
		headermenu.style.display = "none";
	} else {
		headermenu.style.display = "block";
	}
}

function showHideControlsPopup () {
	var controlspopup = document.getElementById('controlspopup');
	var gauze = document.getElementById('gauze');
	if (controlspopup.style.display == "block") {
		controlspopup.style.display = "none";
		gauze.style.display = "none";
	} else {
		controlspopup.style.display = "block";
		gauze.style.display = "block";
	}
}

function showHideSaveSelectionPopup () {
	var saveselectionpopup = document.getElementById('saveselectionpopup');
	var gauze = document.getElementById('gauze');
	if (saveselectionpopup.style.display == "block") {
		saveselectionpopup.style.display = "none";
		gauze.style.display = "none";
	} else {
		saveselectionpopup.style.display = "block";
		gauze.style.display = "block";
	}
}

function selectUnselectSnapshot(element) {
	var snapshotgauze = element.getElementsByClassName('snapshotgauze')[0];
	if (snapshotgauze.style.display == "block"){
		snapshotgauze.style.display = "none";
		element.setAttribute('data-selected', "yes");
	} else {
		snapshotgauze.style.display = "block";
		element.setAttribute('data-selected', "no");
	}
}

function saveSelection() {
	var saveselectionfilename = document.getElementById('saveselectionfilename').value;
	
	var inverseselected = document.querySelectorAll('[data-selected="no"]');
	var rootdirectory = document.getElementById('rootdirectory').value;
	var inputfilename = document.getElementById('inputfilename').value;
	var url = 'JSONhandler?function=saveunblurselection';
	url += "&inputfilename=" + inputfilename;

	if(saveselectionfilename){
		url += "&outputfilename=" + rootdirectory + "/" + saveselectionfilename;
	}
	url += "&inverseselection=";
	for (var i = inverseselected.length - 1; i >= 0; i--) {
		url += inverseselected[i].getAttribute("data-id") + ",";
	} 
	postAjax(url, function(data){showHideSaveSelectionPopup()});
}

setTitle();
getFileviewerData();
