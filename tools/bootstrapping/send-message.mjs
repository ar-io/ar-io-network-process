

import { message, result } from '@permaweb/aoconnect';


const processId = 'ario-bootstrap-test-1'

async function sendMessage(data) {
    const response = await message({
        process: processId,
        tags: [{
            name: 'Action',
            value: 'Load-Balances'
        }],
        data: JSON.stringify(data)
    })
    return result(response)
}





