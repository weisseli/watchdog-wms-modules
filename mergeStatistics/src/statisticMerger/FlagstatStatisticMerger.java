package statisticMerger;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;

public class FlagstatStatisticMerger extends AbstractStatisticMerger {
	
	public static final String TAB = "\t";
	public static final String HEADER = "number" + TAB + "event" + TAB + "sample";
	public static final String ENDING = "flagstat\\.txt";
	public static final String DATA_FILE = ".*" + ENDING + "$";
	protected static final String MERGER_NAME = "FlagstatMerger";
	
	// Available module names
	private static final String MODULE_IDX = "Flagstat";
	protected static final ArrayList<String> MODULE_NAMES = new ArrayList<String>();
	
	 /**
     * add the used settings
     */
    static {
        // add modules
        MODULE_NAMES.add(MODULE_IDX);
        
        addModuleNames(MERGER_NAME, MODULE_NAMES);
    }
	
	@Override
	protected boolean extractTable(String moduleName, String file, BufferedWriter outfile, boolean writeHeader) {
		File f = new File(file);

		// test if correct file is given
		if(!f.isFile() || !f.canRead() || !f.getName().matches(DATA_FILE))
			return false;

		// open file
		try {
			// write header
			if(writeHeader) {
				outfile.write(HEADER);
				outfile.newLine();
			}
	
			// process the file
			String line;
			BufferedReader r = new BufferedReader(new FileReader(f));

			String name = f.getParentFile().getName();
			// read lines
			while((line = r.readLine()) != null) {
				// process the line
				line = line.replaceAll(" \\+ 0 ", "");
				line = line.replaceAll("^([0-9]+)", "$1\t");
				line = line.replaceAll("\\(.+\\)", "");
				line = line.replaceAll("[ ]+$", "");
				outfile.write(line);
				outfile.write(TAB);
				outfile.write(name);
				outfile.newLine();
			}
			outfile.flush();
			// close the file
			r.close();
			return true;
		}
		catch(Exception e) {
			e.printStackTrace();
		}
		return false;
	}

	@Override
	public String getNameOfStatisticFile() {
		return DATA_FILE;
	}

	@Override
	public String getMergerName() {
		return MERGER_NAME;
	}

	@Override
	public void finalize(BufferedWriter outfile) throws IOException {}
}
