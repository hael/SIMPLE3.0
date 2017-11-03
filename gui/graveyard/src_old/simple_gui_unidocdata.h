#ifndef SIMPLE_GUI_UNIDOCDATA_H_INCLUDED
#define SIMPLE_GUI_UNIDOCDATA_H_INCLUDED

struct UniDoc {
	std::vector<std::string> data;
};

void readUniDoc(UniDoc *unidoc, std::string filename){
	std::ifstream input;
	std::string line;
	input.open(filename.c_str());
	if(input.is_open()){
		while(getline(input, line)){
			unidoc->data.push_back(line);
		}
		input.close();
	} else {
		std::cout << "no unidoc" << std::endl;
	}
}

void getUniDocLineValue(UniDoc *unidoc, int line, std::string key, std::string &value){
	std::string		unidocline;
	
	unidocline = unidoc->data[line];
	
	getKeyValFromString(&value, unidocline, key);
}

#endif
