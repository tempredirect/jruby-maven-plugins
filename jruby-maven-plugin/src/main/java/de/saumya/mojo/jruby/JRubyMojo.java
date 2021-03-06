package de.saumya.mojo.jruby;

import java.io.File;
import java.io.IOException;

import org.apache.maven.plugin.MojoExecutionException;

import de.saumya.mojo.ruby.script.Script;
import de.saumya.mojo.ruby.script.ScriptException;

/**
 * executes the jruby command.
 * 
 * @goal jruby
 * @requiresDependencyResolution test
 */
public class JRubyMojo extends AbstractJRubyMojo {

    /**
     * ruby code which gets executed.
     * 
     * @parameter default-value="${jruby.script}"
     */
    protected String script = null;

    /**
     * ruby file which gets executed.
     * 
     * @parameter default-value="${jruby.file}"
     */
    protected File file = null;

    @Override
    public void executeJRuby() throws MojoExecutionException, IOException,
            ScriptException {
        Script s;
        if (this.script != null && this.script.length() > 0) {
            s = this.factory.newScript(this.script);
        } else if (this.file != null) {
            s = this.factory.newScript(this.file);
        } else {
            s = this.factory.newArguments();
        }
        s.addArgs(this.args);
        if (s.isValid()) {
            s.executeIn(launchDirectory());
        } else {
            getLog()
                    .warn(
                            "no arguments given. use -Djruby.args=... or -Djruby.script=... or -Djruby.file=...");
        }
    }
}