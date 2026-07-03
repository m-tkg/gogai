var ExtensionPreprocessingJS = function() {};

ExtensionPreprocessingJS.prototype = {
    run: function(arguments) {
        arguments.completionFunction({
            "title": document.title,
            "URL": document.URL
        });
    }
};

var ExtensionPreprocessingJS = new ExtensionPreprocessingJS;
