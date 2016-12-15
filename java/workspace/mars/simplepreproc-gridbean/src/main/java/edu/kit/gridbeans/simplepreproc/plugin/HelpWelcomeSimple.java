/**
 * 
 */
package edu.kit.gridbeans.simplepreproc.plugin;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Container;
import java.awt.Dimension;
import java.awt.FlowLayout;
import java.awt.Toolkit;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

import javax.swing.JButton;
import javax.swing.JDialog;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.SpringLayout;

/**
 * @author Frederic-PC.linux64
 *
 */
public class HelpWelcomeSimple extends JDialog {

	/**
	 * Add UID
	 */
	private static final long serialVersionUID = 5486361627846234269L;
    private final static int WIDTH = 800;       /**width dimension of the window*/
    private final static int HEIGHT = 580;      /**height dimension of the window*/
	
    private JButton mButtonContinue = null;
	@SuppressWarnings("unused")
	private JButton	mClicked = null;
	private ActionListener mButtonListener = new ButtonListener();

	public HelpWelcomeSimple() {
		super();
		
		setTitle("Help Using the Welcome Panel (java)"+Version.getVersionSimpleGridBean());
		setModal(true);
		setSize(WIDTH, HEIGHT);

		Container contentPane = getContentPane();

		contentPane.setLayout(new BorderLayout());

		JPanel imagePanel = new JPanel(new FlowLayout());

		imagePanel.setBackground(Color.WHITE);

		//TODO: need to fix the path name for the 
		JLabel image = new JLabel(GuiUtils.makeImageIconFromJarredImage("./sample.gif"));
		imagePanel.add(image);
		contentPane.add(imagePanel,BorderLayout.NORTH);

		JPanel msgPanel = new JPanel(new SpringLayout());

		msgPanel.setBackground(Color.WHITE);

		String msg =
		    "<html>"
		    +"<table>"
		    +"<tr><td>"
		    
		    // The select BigDFT GridBean developper
		    + "<h2 style='font-family: \"Luxi Sans\", \"Bitstream Vera Sans\", \"Lucida Grande\", \"Trebuchet MS\", helvetica, verdana, arial, sans-serif; color: #800000'>" +
		    "What to do first?</h2>"
		    + "<p style='font-family: \"Luxi Sans\", \"Bitstream Vera Sans\", \"Lucida Grande\", \"Trebuchet MS\", helvetica, verdana, arial, sans-serif; font-size: medium'>" +
		    "First select the start you wish to do either " +
		    "" +
		    "</p>"

		    // What happens next?
		    + "<h2 style='font-family: \"Luxi Sans\", \"Bitstream Vera Sans\", \"Lucida Grande\", \"Trebuchet MS\", helvetica, verdana, arial, sans-serif; color: #800000'>" +
		    "What happens next?</p>"
		    + "<p style='font-family: \"Luxi Sans\", \"Bitstream Vera Sans\", \"Lucida Grande\", \"Trebuchet MS\", helvetica, verdana, arial, sans-serif; font-size: medium'>" +
		    "Once that you have selected the starting configuration of the preprocessing, that is if one has the Boxfile files or not," +
		    " you must go the panel in quetions and modify the " +
		    "parameters correctly" +
		    "" +
		    "" +
		    "<br>" +
		    "<br>" +
		    "Once all the parameters have been correctly adjusted you may click the run/start button in the main menu.</p>"
		    
		    // About the the GriDBean
		    + "<h2 style='font-family: \"Luxi Sans\", \"Bitstream Vera Sans\", \"Lucida Grande\", \"Trebuchet MS\", helvetica, verdana, arial, sans-serif; color: #800000'>" +
		    "General use of the GridBean</p>"
		    + "<p style='font-family: \"Luxi Sans\", \"Bitstream Vera Sans\", \"Lucida Grande\", \"Trebuchet MS\", helvetica, verdana, arial, sans-serif; font-size: medium'>" +
		    "The <Strong>Boxfile</Strong> " +
		    "<br>" +
		    "<br>" +
		    "</p>"
		    		    
		    + "</td></tr>"
		    + "</table>"
		    
		    + "</html>";
		
		// Add the tabs to the frame's content panel
		msgPanel.add(GuiUtils.makeJLabel(msg,true));
		SpringLayoutUtils.makeCompactGrid(msgPanel, 1, 1, 5, 5, 5, 5);		
		contentPane.add(BorderLayout.CENTER,msgPanel);

		//add the button in the footer
		JPanel buttonPanel = new JPanel(new FlowLayout());
		
		buttonPanel.setBackground(Color.WHITE);
		
		mButtonContinue = GuiUtils.makeJButton("Continue", mButtonListener);
		buttonPanel.add(mButtonContinue);
		
		contentPane.add(BorderLayout.SOUTH, buttonPanel);

		Dimension me = getSize();
		Dimension screen = Toolkit.getDefaultToolkit().getScreenSize();

		int left = (screen.width - me.width) / 2;
		int top = (screen.height - me.height) / 2;

		setLocation(left,top);
		
	    }
	    
		class ButtonListener implements ActionListener {
			public void actionPerformed(ActionEvent e)
			{
				if (e.getSource() == mButtonContinue) doContinue();
			}
		}
		protected void doContinue() {
	    	mClicked = mButtonContinue;
	    	setVisible(false);
	    	dispose();
	    }	
}


