/* Copyright 2012+ Denis Badanin <denis.badanin@gmail.com>
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 *
 */

using Gtk;

public class pinimap : GLib.Object {

    public Window win;
    private WebKit.WebView Wv;
    private TreeView TVFiles;
    private TreeModel TModel;
    private ListStore dataStore;
    private Entry ESearch;
    private const int COL_IMG = 0;
    private const int COL_FIL = 1;
    private const int COL_LAT = 2;
    private const int COL_LNG = 3;
    private const int COL_PTH = 4;
    private const string JMSJ_XY = "coords";
    private const string JMSJ_NO_LOC = "no_results";
    HBox hb;
    
    public pinimap() {
        var gbldr = new Builder();
        try {   
            gbldr.add_from_file("main.glade");
            win = gbldr.get_object("WMain") as Window;
            win.destroy.connect(Gtk.main_quit);

            gbldr.connect_signals(this);
            webkit_connect(gbldr);
            TVFiles = gbldr.get_object("TVFiles") as TreeView;
            TModel = TVFiles.get_model();
            TreeSelection ts = TVFiles.get_selection();
            ts.set_mode(SelectionMode.MULTIPLE);
            ts.changed.connect(on_selection_changed);
            dataStore = gbldr.get_object("dataStore") as ListStore;
            ESearch = gbldr.get_object("ESearch") as Entry;
            hb = gbldr.get_object("hbox1") as HBox;
        } catch (Error e) {
            stderr.printf ("Could not load UI: %s\n", e.message);
        } 
    } 
    
    //Activate and connect Webkit.WebView
    private void webkit_connect(Builder gbldr) {
        ScrolledWindow sw = gbldr.get_object("sw_browser") as ScrolledWindow;
        Wv = new WebKit.WebView();
        Wv.console_message.connect(on_java_message);
        sw.add(Wv);

        string doc;
        try {
            FileUtils.get_contents("init.html", out doc);
        } catch (Error e) {
            stderr.printf ("Error: %s\n", e.message);
        }
        Wv.load_html_string(doc, "");
        //stderr.printf(GLib.Win32.getlocale());
    }

    public bool on_java_message(string message, int line_number, string source_id) {
        stderr.printf("Java Message us: %s\n", message);
        //Parce messages
        string[] tokens = {"tmp"};
        try {
            var rx = new Regex("\\s");
            tokens = rx.split(message);
        } catch (RegexError e) {
            stderr.printf("Error: %s\n", e.message);
        }
        //Check if first token set the coordinates
        if (tokens[0] == JMSJ_XY) {
            var ts = TVFiles.get_selection();
            TreeModel tm;
            TreeIter ti;
            List<TreePath> sl = ts.get_selected_rows(out tm);
            for (int i = 3; i < tokens.length; i++) {
                foreach (TreePath tp in sl) {
                    tm.get_iter(out ti, tp);
                    string name;
                    tm.get(ti, COL_FIL, out name);
                    if (name == tokens[i]) {
                        dataStore.set(ti, COL_LAT, double.parse(tokens[1]),
                                   COL_LNG, double.parse(tokens[2]));
                        break;
                    }
                }
            }
        }

        if (tokens[0] == JMSJ_NO_LOC) {
//            ESearch.grab_focus;
            ESearch.select_region(0, -1);
        }
        return true;
    }

    public void on_selection_changed() {
        var ts = TVFiles.get_selection();
        TreeModel tm;
        TreeIter ti;
        List<TreePath> sl = ts.get_selected_rows(out tm);
        Wv.execute_script("clear_markers()");
        foreach (TreePath tp in sl) {
            tm.get_iter(out ti, tp);

            string name;
            double lat;
            double lng;
            tm.get(ti, COL_FIL, out name,
                       COL_LAT, out lat,
                       COL_LNG, out lng);

            string outs = "file_list = '%s'; add_marker(%s, %s)".printf(name, 
              lat.to_string(), lng.to_string());
            stderr.printf(outs + "\n");
            Wv.execute_script(outs);
        }
    }

    [CCode (instance_pos = -1)]
    public void on_bopen_click(Widget source) {       
        var odlg = new FileChooserDialog("Select File", win, 
          FileChooserAction.OPEN,
          Stock.CANCEL, ResponseType.CANCEL,
          Stock.OPEN, ResponseType.ACCEPT, null);
        var fltr = new FileFilter();
        fltr.set_name("JPEG Image");
        fltr.add_mime_type("image/jpeg");
        odlg.add_filter(fltr);
        odlg.set_select_multiple(true);
        
        
        Regex reg = new Regex("[\\w_.-]*?(?=[\\?\\#])|[\\w_.-]*$");
        MatchInfo match;
        var exiv2 = new GExiv2.Metadata();
        if (odlg.run() == ResponseType.ACCEPT) {
            //Let Read selected files
            SList<string> files_name = odlg.get_filenames();

            TreeIter iter;
            string path;
            string name;
            double alt = 0;
            double lat = 0;
            double lng = 0;
            GExiv2.Orientation exor = GExiv2.Orientation.NORMAL;
            Gdk.InterpType it = Gdk.InterpType.NEAREST;
            Gdk.PixbufRotation pbrt = Gdk.PixbufRotation.NONE;
            for (int i = 0; i < files_name.length(); i++) {
                path = files_name.nth_data(i);

                //check for duplicates
                string tm_path;
                bool found = false;
                if (dataStore.get_iter_first(out iter)) {
                    do {
                        TModel.get(iter, COL_PTH, out tm_path);                  
                        if (path == tm_path) {
                            found = true;
                            break;
                        }                                            
                    } while (TModel.iter_next(ref iter));
                }
                if (found) {
                    stderr.printf("Duplicate found!\n");
                    continue;
                }
                
                //adding files
                reg.match(path, 0, out match);
                name = match.fetch(0);
                
                try {
                exiv2.open_path(path);
                exiv2.get_gps_info(out lng, out lat, out alt);                   
                exor = exiv2.get_orientation();
                } catch (Error e) {
                    stderr.printf("Error: %s\n", e.message);
                }

                dataStore.append(out iter);
                switch (exor) {
                    case GExiv2.Orientation.ROT_90: 
                        pbrt = Gdk.PixbufRotation.CLOCKWISE;
                        break;
                    case GExiv2.Orientation.ROT_180: 
                        pbrt = Gdk.PixbufRotation.UPSIDEDOWN;
                        break;
                    case GExiv2.Orientation.ROT_270: 
                        pbrt = Gdk.PixbufRotation.COUNTERCLOCKWISE;
                        break;
                }

                try {
                    Gdk.Pixbuf pb = new Gdk.Pixbuf.from_file(path).
                      scale_simple(40,40, it).
                      rotate_simple(pbrt);
                    dataStore.set(iter, COL_IMG, pb,
                      COL_FIL, name, 
                      COL_LAT, lat,
                      COL_LNG, lng,
                      COL_PTH, path);
                } catch (Error e) {
                    stderr.printf("Error: %s\n", e.message);
                }
            }
        }
        odlg.destroy();
    }

    [CCode (instance_pos = -1)]
    public void on_BSave_clicked(Widget source) {
        var exiv2 = new GExiv2.Metadata();
        string path;
        double lng;
        double lat;
        TreeIter it;
        if (dataStore.get_iter_first(out it)) {
            do {
                dataStore.get(it, COL_PTH, out path,
                    COL_LNG, out lng, COL_LAT, out lat);
//                stdout.printf("Saving %s\n", path);
                try {
                    exiv2.open_path(path);
                    exiv2.set_gps_info(lng, lat, 0);
                    exiv2.save_file(path);
                } catch (Error e) {
                    stderr.printf ("Error: %s\n", e.message);
                }

            } while (dataStore.iter_next(ref it));
        }
    }

    [CCode (instance_pos = -1)]
    public void on_BClear_clicked(Widget source) {
        Wv.execute_script("clear_markers()");
        dataStore.clear();
    }

    [CCode (instance_pos = -1)]
    public void on_BSearch_clicked(Widget source) {
        string addr = ESearch.get_text();
        if (addr == "" ) return;
        Wv.execute_script("request = '%s'; pan_to_address()".printf(addr));
        //TODO Set focus to ESearch
//        Widget w;
//        w.send_focus_change();
        
//        hb.child_focus();
//        ESearch.grab_focus
    }
    
    [CCode (instance_pos = -1)]
    public void on_ESearch_activate(Widget source) {
        on_BSearch_clicked(ESearch);
    }

    [CCode (instance_pos = -1)]
    public void on_ESearch_icon_press(Widget source, EntryIconPosition p0, Gdk.Event p1) {
        if (ESearch.text != "") {
            ESearch.text = "";
        }
    }

    [CCode (instance_pos = -1)]
    public void on_BCenter_clicked(Widget source) {
        Wv.execute_script("center_markers()");
    }

}

public class app : GLib.Object {
    public static int main(string[] args) {
        Gtk.init(ref args);

        var h = new pinimap();    
        h.win.show_all();
        Gtk.main();
        return 0;
    }   
}
