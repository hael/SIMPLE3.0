package edu.kit.gridbeans.simpleprime.plugin;
import javax.swing.Icon;
import com.intel.gpe.clients.api.Client;
import com.intel.gpe.gridbeans.plugins.swing.GridBeanPlugin;
import com.intel.gpe.util.defaults.preferences.INode;
import com.intel.gpe.gridbeans.plugins.DataSetException;
import edu.kit.gridbeans.simpleprime.SimplePrimeGridBean;



public class SimplePrimePlugin extends GridBeanPlugin 
{

  @Override
  public void initialize(Client client, INode node) 
  {
    super.initialize(client, node);
   
    try {
    addInputPanel(new SimplePrimePanel(client, node));
    addInputPanel(new ParameterPanel(client, node));
    } catch (DataSetException de) {
    	System.out.println("An execption occurs during linking the components to the gridbean model: " + de.toString());
    }
  }

  public Icon getIcon() 
  {
    return getOrCreateIcon(SimplePrimeGridBean.class, "images/icon.png");
  }

}
