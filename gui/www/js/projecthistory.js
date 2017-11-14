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

function setTitle() {
	var headerproject = document.getElementById('headerproject');
	var projectselector = parent.document.getElementById('projectselector');
	var project = projectselector.options[projectselector.selectedIndex].getAttribute('data-projectname');
	if (project){
		headerproject.innerHTML = projectselector.options[projectselector.selectedIndex].getAttribute('data-projectname');
	} else {
		document.getElementById('header').innerHTML = "";
	}
}

function getJobs () {
	var projectselector = parent.document.getElementById('projectselector');
	getAjax('JSONhandler?function=getjobs&table=' + projectselector.options[projectselector.selectedIndex].getAttribute('data-projecttable'), function(data){addJobs(data)});
}

function addJobs(data){
	var JSONdata = JSON.parse(data);
	
	var historytable = document.getElementById('historytable');
	for (var i = 0; i < JSONdata.jobs.length; i++) {
		var row = historytable.insertRow();
		var cell1 = row.insertCell();
		var cell2 = row.insertCell();
		var cell3 = row.insertCell();
		var cell4 = row.insertCell();
		var cell5 = row.insertCell();
		cell1.innerHTML = JSONdata.jobs[i].id;
		cell2.innerHTML = JSONdata.jobs[i].jobtype;
		cell3.innerHTML = JSONdata.jobs[i].jobstatus;
		cell3.innerHTML = JSONdata.jobs[i].jobstatus;
		cell4.innerHTML = JSONdata.jobs[i].jobname;
		cell4.title = JSONdata.jobs[i].jobdescription;
		cell4.style.width = "100%";
		var gearimage = document.createElement("img");
		gearimage.src = "img/gear.png";
		gearimage.onclick = function(){
			var jobmenu = this.parentNode.getElementsByClassName('jobmenu')[0];
			if(jobmenu.style.display == "block"){
				jobmenu.style.display = "none";
			} else {
				jobmenu.style.display = "block";
			}
		}
		cell5.appendChild(gearimage);
		var jobmenu = document.createElement("div");
		jobmenu.className = "jobmenu";
		var viewoutput = document.createElement("div");
		viewoutput.innerHTML = "View Output";
		viewoutput.setAttribute('data-jobfolder', JSONdata.jobs[i].jobfolder);
		viewoutput.setAttribute('data-jobtype', JSONdata.jobs[i].jobtype);
		viewoutput.onclick = function(){viewOutput(this)};
		jobmenu.appendChild(viewoutput);
		cell5.appendChild(jobmenu);
	}
}

function viewOutput(element){		
	var mainpaneiframe = parent.document.getElementById('mainpaneiframe');
	if (element.getAttribute('data-jobtype') == "preproc"){
		mainpaneiframe.src = "pipelineview.html?folder=" + element.getAttribute('data-jobfolder');
	} else if (element.getAttribute('data-jobtype') == "stream2d"){
		mainpaneiframe.src = "2dview.html?folder=" + element.getAttribute('data-jobfolder');
	}else if (element.getAttribute('data-jobtype') == "prime2d"){
		mainpaneiframe.src = "2dview.html?folder=" + element.getAttribute('data-jobfolder');
	}

}

setTitle();
getJobs();