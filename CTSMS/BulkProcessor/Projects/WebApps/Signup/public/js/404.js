

function initPrimeUI(context) {

    $('#messages').puimessages();
    if (context.apiError != null) {
        setMessages('warn', context.apiError ); 
    }

}