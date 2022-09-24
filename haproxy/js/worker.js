importScripts('/js/argon2.js');

onmessage = async function(e) {
	const [userkey, challenge, diffString, argonOpts, id, threads] = e.data;
	console.log('Worker thread', id, 'started');
	let i = id;
	while(true) {
		const hash = await argon2.hash({
			pass: challenge + i.toString(),
			salt: userkey,
			...argonOpts,
		});
		// This throttle seems to really help some browsers not stop the workers abruptly
		i % 10 === 0 && await new Promise(res => setTimeout(res, 10));
		if (hash.hashHex.startsWith(diffString)) {
			console.log('Worker', id, 'found solution');
			postMessage([id, i]);
			break;
		}
		i+=threads;
	}
}
